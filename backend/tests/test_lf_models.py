"""The real matching models (skipped unless they're installed: scripts/fetch_match_models.py)."""
import io

import numpy as np
import pytest

from app.matching.engine import score_pair
from app.matching.trigger import model_dir

onnxruntime = pytest.importorskip("onnxruntime")
from app.matching.models import models_present, onnx_embedder  # noqa: E402

pytestmark = pytest.mark.skipif(not models_present(model_dir()), reason="matching models not downloaded")


@pytest.fixture(scope="module")
def embedder():
    return onnx_embedder(model_dir())


def test_descriptions_of_the_same_item_score_strong(embedder):
    lost = embedder.text("Lost my black JBL wireless earbuds in a small charging case near the library")
    found = [embedder.text(t) for t in ("Found a brown wallet near the main gate",
                                        "Found wireless earphones in a black case on a library reading table",
                                        "Calculator (Casio) found in physics department exam hall")]
    sims = [float(np.dot(lost, f)) for f in found]
    assert len(lost) == 384 and int(np.argmax(sims)) == 1
    assert score_pair(sims[1], None, None, True)[0] >= 0.75
    assert score_pair(sims[0], None, None, False)[0] < 0.4


def test_photos_and_text_share_one_space(embedder):
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (640, 480), (200, 30, 30)).save(buf, "JPEG")
    photo = embedder.image(buf.getvalue())
    assert len(photo) == 512 and abs(np.linalg.norm(photo) - 1) < 1e-4
    assert len(embedder.clip_text("a red square")) == 512
    assert embedder.image(b"not an image") is None
