"""The three small embedding models behind Lost & Found matching.

- all-MiniLM-L6-v2 (90 MB): description vs description.
- MobileCLIP-S0 image encoder (45 MB): photo vs photo.
- MobileCLIP-S0 text encoder (170 MB): description vs photo (CLIP puts both in one space).

All three run on ONNX Runtime (no PyTorch), fp32, one thread. Measured on an M-series Mac:
~7 ms per description, ~36 ms per photo; expect 2-3x that on a 1-vCPU Graviton Lambda.
The int8 builds were slower on ARM and the int8 image model lost accuracy, so they aren't used.

Files come from scripts/fetch_match_models.py into match_model_dir. Nothing here is imported by
the API unless matching runs in-process (match_mode "inline"); the API Lambda doesn't ship it.
"""
import io
import logging
import os
from functools import lru_cache
from pathlib import Path
from typing import Protocol

import numpy as np

log = logging.getLogger("campushub.matching")

# Model ids stored with each vector, so a model change can't silently compare unlike vectors.
TEXT_MODEL = "minilm-l6-v2"
CLIP_TEXT_MODEL = "mobileclip-s0-text"
CLIP_IMAGE_MODEL = "mobileclip-s0-image"

MODEL_FILES = {
    "minilm": ("all-MiniLM-L6-v2/onnx/model.onnx", "all-MiniLM-L6-v2/tokenizer.json"),
    "clip_text": ("mobileclip_s0/onnx/text_model.onnx", "mobileclip_s0/tokenizer.json"),
    "clip_image": ("mobileclip_s0/onnx/vision_model.onnx", None),
}
CLIP_SIZE = 256        # MobileCLIP-S0: shortest edge 256, centre crop 256, pixels / 255, no mean/std
CLIP_CONTEXT = 77
MAX_TEXT_TOKENS = 256


class Embedder(Protocol):
    """Unit-length vectors. Tests swap in a fake; the real one is OnnxEmbedder."""
    def text(self, description: str) -> list[float]: ...
    def clip_text(self, description: str) -> list[float]: ...
    def image(self, data: bytes) -> list[float] | None: ...   # None: the file isn't a readable image


def models_present(model_dir: str | os.PathLike) -> bool:
    root = Path(model_dir)
    return all((root / f).is_file() for pair in MODEL_FILES.values() for f in pair if f)


def _unit(v: np.ndarray) -> list[float]:
    return (v / np.linalg.norm(v)).astype(np.float32).tolist()


class OnnxEmbedder:
    def __init__(self, model_dir: str | os.PathLike):
        import onnxruntime as ort
        from tokenizers import Tokenizer

        root = Path(model_dir)
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        opts.inter_op_num_threads = 1

        def session(name: str):
            return ort.InferenceSession(str(root / MODEL_FILES[name][0]), opts, providers=["CPUExecutionProvider"])

        self._minilm = session("minilm")
        self._clip_text = session("clip_text")
        self._clip_image = session("clip_image")
        self._tok = Tokenizer.from_file(str(root / MODEL_FILES["minilm"][1]))
        self._tok.enable_truncation(MAX_TEXT_TOKENS)
        self._clip_tok = Tokenizer.from_file(str(root / MODEL_FILES["clip_text"][1]))

    def text(self, description: str) -> list[float]:
        enc = self._tok.encode(description)
        ids = np.array([enc.ids], dtype=np.int64)
        mask = np.array([enc.attention_mask], dtype=np.int64)
        hidden = self._minilm.run(None, {"input_ids": ids, "attention_mask": mask,
                                         "token_type_ids": np.zeros_like(ids)})[0]
        pooled = (hidden * mask[..., None]).sum(1) / mask.sum(1, keepdims=True)   # mean pooling
        return _unit(pooled[0])

    def clip_text(self, description: str) -> list[float]:
        ids = self._clip_tok.encode(description).ids[:CLIP_CONTEXT]
        ids += [0] * (CLIP_CONTEXT - len(ids))
        return _unit(self._clip_text.run(None, {"input_ids": np.array([ids], dtype=np.int64)})[0][0])

    def image(self, data: bytes) -> list[float] | None:
        pixels = _clip_pixels(data)
        if pixels is None:
            return None
        return _unit(self._clip_image.run(None, {"pixel_values": pixels})[0][0])


def _clip_pixels(data: bytes) -> np.ndarray | None:
    from PIL import Image, ImageOps, UnidentifiedImageError
    try:
        import pillow_heif
        pillow_heif.register_heif_opener()   # HEIC photos from iPhones
    except ImportError:
        pass
    try:
        img = Image.open(io.BytesIO(data))
        img = ImageOps.exif_transpose(img).convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError):
        log.warning("Skipping a photo that couldn't be decoded")
        return None
    w, h = img.size
    scale = CLIP_SIZE / min(w, h)
    img = img.resize((max(CLIP_SIZE, round(w * scale)), max(CLIP_SIZE, round(h * scale))), Image.BICUBIC)
    w, h = img.size
    left, top = (w - CLIP_SIZE) // 2, (h - CLIP_SIZE) // 2
    arr = np.asarray(img.crop((left, top, left + CLIP_SIZE, top + CLIP_SIZE)), dtype=np.float32) / 255.0
    return arr.transpose(2, 0, 1)[None]


@lru_cache
def onnx_embedder(model_dir: str) -> OnnxEmbedder:
    """Loaded once per process (a warm Lambda keeps it)."""
    return OnnxEmbedder(model_dir)
