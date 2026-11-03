"""Suggest an existing Buy & Sell / Lost & Found category from a listing's title (future plan §2.4).

Nearest existing category only: it never invents a category, and stays quiet when nothing fits.

How a title is scored against each category (cosine similarity of bge-small-en-v1.5 embeddings):
- the category as a phrase, "a <name> item for sale", not the bare name. Bare one-word names
  ("Plant", "Bottle") sit close together in embedding space, which is what made the first version
  (all-MiniLM-L6-v2 on bare names, threshold 0.2) suggest "Bottle" for "plant";
- the closest of the category's recent listings (or Lost & Found reports): real titles say far
  more about what a category holds than its name does, and this improves as listings accumulate.
  score = (1 - EXAMPLE_WEIGHT) * phrase + EXAMPLE_WEIGHT * best example (phrase only if it has none).
A suggestion needs score >= category_suggest_threshold AND a lead of category_suggest_margin over
the runner-up, so an ambiguous title gets no suggestion rather than a coin flip.

Model: BAAI/bge-small-en-v1.5, int8 ONNX (Xenova export, 34 MB), CLS pooling, the bge query
instruction on the title. ~3 ms per title on one CPU thread, so it runs in the API itself for the
typeahead. Chosen by scripts/calibrate_category_suggest.py (87 labelled titles, 1 Nov 2026) over
all-MiniLM-L6/L12, gte-small, e5-small, arctic-embed-xs, mxbai-xsmall, an NLI re-ranker and
Qwen2.5-0.5B-Instruct naming a category (24 wrong suggestions, ~260 ms, 833 MB). Results:
  old (MiniLM, bare names, 0.2):  top pick right 56/79 titles; at a safe threshold 23 suggested, 55 silent
  this:                           top pick right 71/79; at 0.52 / 0.03: 55 right, 2 wrong, 22 silent,
                                  no suggestion for the 8 titles that fit no category
If the model files or onnxruntime are missing, suggestion is unavailable and callers get None.
"""
import asyncio
import importlib.util
import logging
from functools import lru_cache
from pathlib import Path

import asyncpg

from .config import get_settings
from .matching.trigger import model_dir

log = logging.getLogger("campushub.categories")

MODEL_FILE = "bge-small-en-v1.5/onnx/model_quantized.onnx"
TOKENIZER_FILE = "bge-small-en-v1.5/tokenizer.json"
QUERY_PREFIX = "Represent this sentence for searching relevant passages: "
EXAMPLE_WEIGHT = 0.3
EXAMPLES_PER_CATEGORY = 20
MAX_CACHED_VECTORS = 20_000

# Recent titles per category: Buy & Sell listings, or Lost & Found report descriptions.
_EXAMPLES = {
    "bs_categories": """
        SELECT category_id, title AS text FROM (
            SELECT category_id, title, row_number() OVER (PARTITION BY category_id ORDER BY created_at DESC) AS n
            FROM listings WHERE deleted_at IS NULL) x
        WHERE n <= $1""",
    "lf_categories": """
        SELECT category_id, text FROM (
            SELECT category_id, left(description, 120) AS text,
                   row_number() OVER (PARTITION BY category_id ORDER BY created_at DESC) AS n
            FROM (SELECT category_id, description, created_at FROM lost_reports WHERE deleted_at IS NULL
                  UNION ALL
                  SELECT category_id, description, created_at FROM found_reports WHERE deleted_at IS NULL) r) x
        WHERE n <= $1""",
}


def category_phrase(name: str) -> str:
    return f"a {name.strip().lower()} item for sale"


def suggestion_available() -> bool:
    root = Path(model_dir())
    return (importlib.util.find_spec("onnxruntime") is not None
            and (root / MODEL_FILE).is_file() and (root / TOKENIZER_FILE).is_file())


class BgeEmbedder:
    def __init__(self, root: str):
        import onnxruntime as ort
        from tokenizers import Tokenizer

        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        self._session = ort.InferenceSession(str(Path(root) / MODEL_FILE), opts, providers=["CPUExecutionProvider"])
        self._inputs = {i.name for i in self._session.get_inputs()}
        self._tok = Tokenizer.from_file(str(Path(root) / TOKENIZER_FILE))
        self._tok.enable_truncation(64)
        self._tok.enable_padding()
        self._cache: dict[str, "np.ndarray"] = {}

    def embed(self, texts: list[str]):
        """Unit vectors, one row per text (cached: example titles repeat on every request)."""
        import numpy as np

        todo = list(dict.fromkeys(t for t in texts if t not in self._cache))
        for start in range(0, len(todo), 32):
            batch = todo[start:start + 32]
            enc = self._tok.encode_batch(batch)
            ids = np.array([e.ids for e in enc], dtype=np.int64)
            feed = {"input_ids": ids, "attention_mask": np.array([e.attention_mask for e in enc], dtype=np.int64)}
            if "token_type_ids" in self._inputs:
                feed["token_type_ids"] = np.zeros_like(ids)
            cls = self._session.run(None, feed)[0][:, 0]   # CLS pooling
            cls /= np.linalg.norm(cls, axis=1, keepdims=True)
            if len(self._cache) + len(batch) > MAX_CACHED_VECTORS:
                self._cache.clear()
            self._cache.update(zip(batch, cls))
        return np.array([self._cache[t] for t in texts])


@lru_cache
def get_embedder() -> BgeEmbedder:
    return BgeEmbedder(model_dir())


def rank(embedder, title: str, categories: list[tuple[int, str]],
         examples: dict[int, list[str]]) -> list[tuple[int, str, float]]:
    """Every category with its score for this title, best first."""
    title_vec = embedder.embed([QUERY_PREFIX + title])[0]
    phrase = embedder.embed([category_phrase(name) for _, name in categories]) @ title_vec
    ranked = []
    for (cat_id, name), p in zip(categories, phrase):
        texts = examples.get(cat_id)
        score = float(p)
        if texts:
            score = (1 - EXAMPLE_WEIGHT) * score + EXAMPLE_WEIGHT * float((embedder.embed(texts) @ title_vec).max())
        ranked.append((cat_id, name, score))
    return sorted(ranked, key=lambda r: r[2], reverse=True)


def pick(ranked: list[tuple[int, str, float]], threshold: float, margin: float) -> tuple[int, str] | None:
    if not ranked:
        return None
    best = ranked[0]
    runner_up = ranked[1][2] if len(ranked) > 1 else -1.0
    if best[2] < threshold or best[2] - runner_up < margin:
        return None
    return best[0], best[1]


async def suggest_category(conn: asyncpg.Connection, table: str, title: str) -> tuple[int, str] | None:
    """The existing category in [table] (bs_categories or lf_categories) that clearly fits [title], or None."""
    title = " ".join(title.split())
    if not title or not suggestion_available():
        return None
    categories = [(r["id"], r["name"]) for r in await conn.fetch(f"SELECT id, name FROM {table} ORDER BY id")]
    if not categories:
        return None
    examples: dict[int, list[str]] = {}
    for r in await conn.fetch(_EXAMPLES[table], EXAMPLES_PER_CATEGORY):
        examples.setdefault(r["category_id"], []).append(r["text"])
    s = get_settings()
    ranked = await asyncio.to_thread(rank, get_embedder(), title, categories, examples)
    return pick(ranked, s.category_suggest_threshold, s.category_suggest_margin)
