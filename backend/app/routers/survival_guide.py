"""Course survival guide ("Taking it further", rev 6): a one-page summary of a course's feedback,
semester by semester, with sentiment over time.

Built on request from course_feedback; nothing extra is stored. Each feedback belongs to the
semester it was written in (IST): August–December is the "Aug" semester, January–July the
"Jan" semester. Sentiment, themes and advice come from app/sentiment.py, scored per sentence.
The summary is put together from those numbers; once Ask CampusHub (Bedrock) exists, it can
write the summary instead, with this response shape unchanged.
"""
from collections import Counter
from datetime import datetime, timezone
from statistics import mean
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo

import asyncpg
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .. import sentiment
from ..common import not_found
from ..db import get_conn
from ..sentiment_backends import score_sentences

router = APIRouter(tags=["Academic Help"])

IST = ZoneInfo("Asia/Kolkata")
Label = Literal["positive", "mixed", "negative"]
Trend = Literal["improving", "declining", "steady", "not_enough_data"]
MIN_PER_SEMESTER_FOR_TREND = 3
MAX_FEEDBACK = 5000


class Sentiment(BaseModel):
    score: float = Field(description="-1 (negative) to +1 (positive)")
    label: Label
    positive_share: float = Field(description="Share of feedback that is positive, 0 to 1")
    negative_share: float


class Theme(BaseModel):
    theme: str = Field(examples=["workload"])
    mentions: int
    score: float
    label: Label


class Highlights(BaseModel):
    positive: str | None = Field(description="The most positive sentence of the semester")
    negative: str | None = Field(description="The most negative sentence of the semester")


class Semester(BaseModel):
    term: str = Field(examples=["Aug 2025"])
    starts_on: str = Field(examples=["2025-08-01"])
    in_progress: bool
    feedback_count: int
    sentiment: Sentiment
    top_themes: list[Theme]
    highlights: Highlights


class CourseRef(BaseModel):
    id: UUID
    code: str
    name: str
    department_id: UUID
    department_name: str


class SurvivalGuide(BaseModel):
    course: CourseRef
    feedback_count: int
    summary: str
    overall: Sentiment | None
    trend: Trend
    themes: list[Theme]
    advice: list[str] = Field(description="Tips students repeat most, most common first")
    semesters: list[Semester] = Field(description="Oldest first; only semesters with feedback")
    method: Literal["lexicon"] = Field("lexicon", description="How sentiment was computed")
    generated_at: datetime


def _term(created_at: datetime) -> tuple[int, int]:
    """(year, 1) for the Jan semester, (year, 8) for the Aug semester."""
    local = created_at.astimezone(IST)
    return local.year, 8 if local.month >= 8 else 1


def _term_label(term: tuple[int, int]) -> str:
    return f"{'Aug' if term[1] == 8 else 'Jan'} {term[0]}"


def _sentiment(scores: list[float]) -> Sentiment:
    value = mean(scores)
    return Sentiment(score=round(value, 2), label=sentiment.label(value),
                     positive_share=round(sum(sentiment.label(s) == "positive" for s in scores) / len(scores), 2),
                     negative_share=round(sum(sentiment.label(s) == "negative" for s in scores) / len(scores), 2))


def _themes(sentences: list[tuple[str, float]], limit: int | None = None) -> list[Theme]:
    found: dict[str, list[float]] = {}
    for text, value in sentences:
        for theme in sentiment.themes(text):
            found.setdefault(theme, []).append(value)
    ranked = sorted(found.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:limit]
    return [Theme(theme=t, mentions=len(v), score=round(mean(v), 2), label=sentiment.label(mean(v)))
            for t, v in ranked]


def _trend(semesters: list[Semester]) -> Trend:
    """Slope of the semester scores (finished semesters with enough feedback)."""
    points = [s.sentiment.score for s in semesters
              if not s.in_progress and s.feedback_count >= MIN_PER_SEMESTER_FOR_TREND]
    if len(points) < 3:
        return "not_enough_data"
    xs = range(len(points))
    x_bar, y_bar = mean(xs), mean(points)
    slope = sum((x - x_bar) * (y - y_bar) for x, y in zip(xs, points)) / sum((x - x_bar) ** 2 for x in xs)
    return "improving" if slope > 0.08 else "declining" if slope < -0.08 else "steady"


def _summary(code: str, count: int, overall: Sentiment | None, trend: Trend, semesters: list[Semester],
             themes: list[Theme], advice: list[str]) -> str:
    if overall is None:
        return f"No feedback on {code} yet. Be the first to share how it went."
    first, last = semesters[0].term, semesters[-1].term
    span = f"in {first}" if first == last else f"from {first} to {last}"
    mood = {"positive": "mostly positive", "negative": "mostly negative", "mixed": "mixed"}[overall.label]
    parts = [f"Students are {mood} about {code} ({overall.positive_share:.0%} positive, "
             f"{overall.negative_share:.0%} negative across {count} reviews {span})."]
    finished = [s for s in semesters if not s.in_progress and s.feedback_count >= MIN_PER_SEMESTER_FOR_TREND]
    if trend in ("improving", "declining"):
        parts.append(f"Sentiment is {trend}: {finished[0].sentiment.label} in {finished[0].term}, "
                     f"{finished[-1].sentiment.label} in {finished[-1].term}.")
    elif trend == "steady":
        parts.append("Sentiment has stayed about the same across semesters.")
    if themes:
        parts.append("Most discussed: " + ", ".join(f"{t.theme} ({t.label})" for t in themes[:3]) + ".")
    if advice:
        parts.append(f"Common advice: “{advice[0]}”")
    return " ".join(parts)


@router.get("/courses/{course_id}/survival-guide", response_model=SurvivalGuide,
            summary="One-page summary of a course's feedback, per semester, with sentiment over time (guests allowed)")
async def survival_guide(course_id: UUID, conn: asyncpg.Connection = Depends(get_conn)):
    course = await conn.fetchrow(
        """SELECT c.id, c.code, c.name, c.department_id, d.name AS department_name
           FROM courses c JOIN departments d ON d.id = c.department_id WHERE c.id = $1""", course_id)
    if course is None:
        raise not_found("Course")
    rows = await conn.fetch(
        """SELECT content, created_at FROM course_feedback WHERE course_id = $1 AND deleted_at IS NULL
           ORDER BY created_at DESC LIMIT $2""", course_id, MAX_FEEDBACK)

    by_term: dict[tuple[int, int], list[list[tuple[str, float]]]] = {}
    advice: Counter[str] = Counter()
    advice_text: dict[str, str] = {}
    # Every sentence of every feedback in one batch to the sentiment backend (model or Comprehend).
    split = [sentiment.sentences(r["content"]) for r in rows]
    flat = await score_sentences([s for sentences in split for s in sentences])
    position = 0
    for r, sentences in zip(rows, split):
        scored = list(zip(sentences, flat[position:position + len(sentences)]))
        position += len(sentences)
        if not scored:
            continue
        by_term.setdefault(_term(r["created_at"]), []).append(scored)
        for text, _ in scored:
            if sentiment.is_advice(text):
                key = " ".join(text.lower().rstrip(".!").split())
                advice[key] += 1
                advice_text.setdefault(key, text)

    now_term = _term(datetime.now(timezone.utc))
    semesters, all_scores, all_sentences = [], [], []
    for term in sorted(by_term):
        feedback = by_term[term]
        # A feedback's score: the mean of its sentences that carry an opinion (facts like
        # "Quizzes every two weeks" would only pull every score towards 0).
        scores = [mean([v for _, v in fb if v] or [0.0]) for fb in feedback]
        sentences = [pair for fb in feedback for pair in fb]
        best = max(sentences, key=lambda p: p[1])
        worst = min(sentences, key=lambda p: p[1])
        semesters.append(Semester(
            term=_term_label(term), starts_on=f"{term[0]}-{term[1]:02d}-01", in_progress=term == now_term,
            feedback_count=len(feedback), sentiment=_sentiment(scores), top_themes=_themes(sentences, 3),
            highlights=Highlights(positive=best[0] if sentiment.label(best[1]) == "positive" else None,
                                  negative=worst[0] if sentiment.label(worst[1]) == "negative" else None)))
        all_scores += scores
        all_sentences += sentences

    overall = _sentiment(all_scores) if all_scores else None
    trend = _trend(semesters)
    themes = _themes(all_sentences)
    tips = [advice_text[k] for k, _ in sorted(advice.items(), key=lambda kv: (-kv[1], kv[0]))[:5]]
    return SurvivalGuide(
        course=CourseRef(**dict(course)), feedback_count=len(all_scores),
        summary=_summary(course["code"], len(all_scores), overall, trend, semesters, themes, tips),
        overall=overall, trend=trend, themes=themes, advice=tips, semesters=semesters,
        generated_at=datetime.now(timezone.utc))
