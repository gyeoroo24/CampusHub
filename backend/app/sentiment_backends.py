"""Where course-feedback sentiment comes from. One switch, no code change between local and AWS.

  CAMPUSHUB_SENTIMENT_BACKEND=
    local       a small model in the API itself: twitter-roberta-base-sentiment-latest (RoBERTa-base,
                3 classes negative / neutral / positive, int8 ONNX ~126 MB, MIT), fetched by
                scripts/fetch_match_models.py. ~15 ms a sentence on one CPU core.
    comprehend  Amazon Comprehend BatchDetectSentiment (25 sentences a call). Needs
                comprehend:BatchDetectSentiment on the API's role; the region is CAMPUSHUB_COMPREHEND_REGION
                (Comprehend isn't in every region; ap-south-1 has it).
    lexicon     the word list in app/sentiment.py: instant, no model.
    auto        (default) local when the model files are there, else lexicon.

Every backend returns, per sentence, a score from -1 (negative) to +1 (positive): positive
probability minus negative probability for the model and Comprehend, so "neutral" and Comprehend's
"mixed" land near 0. app/sentiment.py's label() turns scores into positive / mixed / negative the same
way whichever backend scored them. If a backend fails (no model, AWS error), it falls back to the
lexicon and logs once, so the survival guide never breaks.
"""
import asyncio
import importlib.util
import logging
from functools import lru_cache
from pathlib import Path
from typing import Protocol

from .config import get_settings
from .matching.trigger import model_dir

log = logging.getLogger("campushub.sentiment")

MODEL = "twitter-roberta-sentiment"
MODEL_FILE = f"{MODEL}/onnx/model_quantized.onnx"
TOKENIZER_FILE = f"{MODEL}/tokenizer.json"
MAX_TOKENS = 128
BATCH = 16
COMPREHEND_BATCH = 25


class SentimentBackend(Protocol):
    name: str

    def scores(self, sentences: list[str]) -> list[float]: ...


class LexiconBackend:
    name = "lexicon"

    def scores(self, sentences: list[str]) -> list[float]:
        from .sentiment import lexicon_score
        return [lexicon_score(s) for s in sentences]


class LocalModelBackend:
    name = "local"

    def __init__(self, root: Path):
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer
        self._np = np
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        self._session = ort.InferenceSession(str(root / MODEL_FILE), opts, providers=["CPUExecutionProvider"])
        self._inputs = {i.name for i in self._session.get_inputs()}
        self._tok = Tokenizer.from_file(str(root / TOKENIZER_FILE))
        self._tok.enable_truncation(MAX_TOKENS)
        self._tok.enable_padding(pad_id=1, pad_token="<pad>")

    def scores(self, sentences: list[str]) -> list[float]:
        np = self._np
        out: list[float] = []
        for i in range(0, len(sentences), BATCH):
            enc = self._tok.encode_batch(sentences[i:i + BATCH])
            feed = {"input_ids": np.array([e.ids for e in enc], dtype=np.int64),
                    "attention_mask": np.array([e.attention_mask for e in enc], dtype=np.int64)}
            logits = self._session.run(None, {k: v for k, v in feed.items() if k in self._inputs})[0]
            probs = np.exp(logits - logits.max(axis=1, keepdims=True))
            probs /= probs.sum(axis=1, keepdims=True)
            out += [float(p[2] - p[0]) for p in probs]   # labels: 0 negative, 1 neutral, 2 positive
        return out


class ComprehendBackend:
    name = "comprehend"

    def __init__(self, region: str):
        import boto3
        self._client = boto3.client("comprehend", region_name=region)

    def scores(self, sentences: list[str]) -> list[float]:
        out: list[float] = []
        for i in range(0, len(sentences), COMPREHEND_BATCH):
            chunk = [s[:4500] for s in sentences[i:i + COMPREHEND_BATCH]]   # Comprehend's per-text byte limit
            result = self._client.batch_detect_sentiment(TextList=chunk, LanguageCode="en")
            by_index = {r["Index"]: r["SentimentScore"] for r in result["ResultList"]}
            for j in range(len(chunk)):
                s = by_index.get(j)
                out.append(float(s["Positive"] - s["Negative"]) if s else 0.0)
        return out


def local_model_available() -> bool:
    root = Path(model_dir())
    return (importlib.util.find_spec("onnxruntime") is not None and (root / MODEL_FILE).is_file()
            and (root / TOKENIZER_FILE).is_file())


@lru_cache
def get_backend() -> SentimentBackend:
    s = get_settings()
    choice = s.sentiment_backend
    try:
        if choice == "comprehend":
            return ComprehendBackend(s.comprehend_region)
        if choice == "local" or (choice == "auto" and local_model_available()):
            return LocalModelBackend(Path(model_dir()))
    except Exception:  # noqa: BLE001 - a missing model or AWS client must not break the page
        log.exception("Sentiment backend %s unavailable; using the word list", choice)
    return LexiconBackend()


async def score_sentences(sentences: list[str]) -> list[float]:
    """Scores from the configured backend, off the event loop. Falls back to the word list on errors."""
    if not sentences:
        return []
    backend = get_backend()
    try:
        return await asyncio.to_thread(backend.scores, sentences)
    except Exception:  # noqa: BLE001
        log.exception("Sentiment backend %s failed; using the word list for this request", backend.name)
        return LexiconBackend().scores(sentences)
