"""Course-feedback sentiment backends (app/sentiment_backends.py): one setting picks the local model,
Amazon Comprehend or the word list, with the same -1..+1 scores."""
import asyncio

import pytest

from app import sentiment_backends as sb
from app.config import Settings


def _backend(monkeypatch, choice: str):
    monkeypatch.setattr(sb, "get_settings", lambda: Settings(sentiment_backend=choice, comprehend_region="ap-south-1"))
    sb.get_backend.cache_clear()
    try:
        return sb.get_backend()
    finally:
        sb.get_backend.cache_clear()


def test_lexicon_backend(monkeypatch):
    b = _backend(monkeypatch, "lexicon")
    assert b.name == "lexicon"
    good, bad = b.scores(["Great course, highly recommend", "Terrible and boring"])
    assert good > 0.25 and bad < -0.25


@pytest.mark.skipif(not sb.local_model_available(), reason="run scripts/fetch_match_models.py for the sentiment model")
def test_local_model_backend(monkeypatch):
    b = _backend(monkeypatch, "local")
    assert b.name == "local"
    good, bad, neutral = b.scores(["The professor explains concepts really clearly.",
                                   "The workload is brutal and the exams are unfair.",
                                   "Assignments are due every Friday."])
    assert good > 0.5 and bad < -0.5 and abs(neutral) < 0.3


def test_comprehend_backend_without_code_changes(monkeypatch):
    """Comprehend's scores map to the same scale; only the setting changes."""
    calls = []

    class FakeComprehend:
        def batch_detect_sentiment(self, TextList, LanguageCode):
            calls.append(len(TextList))
            return {"ResultList": [{"Index": i, "SentimentScore": {"Positive": 0.9, "Negative": 0.05,
                                                                   "Neutral": 0.05, "Mixed": 0.0}}
                                   for i in range(len(TextList))]}

    import boto3
    monkeypatch.setattr(boto3, "client", lambda *a, **k: FakeComprehend())
    b = _backend(monkeypatch, "comprehend")
    assert b.name == "comprehend"
    scores = b.scores([f"sentence {i}" for i in range(30)])
    assert calls == [25, 5] and all(abs(s - 0.85) < 1e-9 for s in scores)


def test_a_failing_backend_falls_back_to_the_word_list(monkeypatch):
    class Broken:
        name = "broken"

        def scores(self, sentences):
            raise RuntimeError("AWS is down")

    monkeypatch.setattr(sb, "get_backend", lambda: Broken())
    assert asyncio.run(sb.score_sentences(["Great course"]))[0] > 0
