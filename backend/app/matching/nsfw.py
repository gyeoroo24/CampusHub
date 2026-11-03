"""Obscene-photo check for automatic flagging (future plan §1.6, app/screening.py).

Model: Falconsai/nsfw_image_detection (ViT-base, Apache-2.0), the int8 ONNX export from
onnx-community/nsfw_image_detection-ONNX (87 MB). 224x224 bilinear resize, pixels scaled to
[-1, 1]; outputs normal / nsfw. ~55 ms per photo on one CPU thread. On 46 ordinary photos the
highest nsfw probability was 0.004, so FLAG_AT leaves a wide margin. It runs after the response
(matcher Lambda, or a background task locally), never on the request path.
"""
import io
import logging
from functools import lru_cache
from pathlib import Path

import numpy as np

log = logging.getLogger("campushub.matching")

MODEL_FILE = "nsfw_image_detection/onnx/model_int8.onnx"
SIZE = 224
NSFW_INDEX = 1   # config id2label: {0: normal, 1: nsfw}
FLAG_AT = 0.8


def nsfw_model_present(model_dir: str) -> bool:
    return (Path(model_dir) / MODEL_FILE).is_file()


class NsfwClassifier:
    def __init__(self, model_dir: str):
        import onnxruntime as ort
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        self._session = ort.InferenceSession(str(Path(model_dir) / MODEL_FILE), opts,
                                             providers=["CPUExecutionProvider"])
        self._input = self._session.get_inputs()[0].name

    def probability(self, data: bytes) -> float | None:
        """Probability the photo is obscene; None if it can't be decoded."""
        from PIL import Image, ImageOps, UnidentifiedImageError
        try:
            import pillow_heif
            pillow_heif.register_heif_opener()
        except ImportError:
            pass
        try:
            img = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
        except (UnidentifiedImageError, OSError, ValueError):
            return None
        x = np.asarray(img.resize((SIZE, SIZE), Image.BILINEAR), dtype=np.float32) / 255.0
        x = ((x - 0.5) / 0.5).transpose(2, 0, 1)[None]
        logits = self._session.run(None, {self._input: x})[0][0]
        p = np.exp(logits - logits.max())
        return float(p[NSFW_INDEX] / p.sum())


@lru_cache
def nsfw_classifier(model_dir: str) -> NsfwClassifier:
    return NsfwClassifier(model_dir)
