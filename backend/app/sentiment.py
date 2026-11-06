"""Sentence-level sentiment, themes and advice for course feedback (used by the survival guide).

Sentence scores come from app/sentiment_backends.py: a local RoBERTa sentiment model, Amazon
Comprehend, or the word list below (VADER-style, tuned to how students write about courses), chosen
by CAMPUSHUB_SENTIMENT_BACKEND with no code change. Every backend gives -1 (negative) to +1 (positive)
per sentence; themes and advice detection below stay rule-based.
"""
import math
import re

WORDS: dict[str, float] = {
    # positive
    "best": 3, "great": 3, "excellent": 3, "loved": 3, "love": 3, "amazing": 3, "fantastic": 3, "brilliant": 3,
    "clear": 2, "clearly": 2, "organised": 2, "organized": 2, "useful": 2, "helpful": 2, "responsive": 2,
    "fair": 2, "manageable": 2, "interesting": 2, "solid": 2, "enjoyed": 2, "enjoy": 2, "recommend": 2,
    "recommended": 2, "engaging": 2, "good": 2, "insightful": 2, "worth": 2, "fun": 2, "approachable": 2,
    "nice": 1, "easy": 1, "genuinely": 1, "structured": 1, "smooth": 1, "doable": 1, "helps": 1,
    "help": 1, "learned": 1, "learnt": 1,
    # negative
    "brutal": -3, "terrible": -3, "worst": -3, "awful": -3, "horrible": -3, "waste": -3, "useless": -3,
    "disconnected": -2, "opaque": -2, "crammed": -2, "rushed": -2, "heavy": -2, "confusing": -2, "boring": -2,
    "unfair": -2, "drags": -2, "uneven": -2, "overloaded": -2, "stressful": -2, "poor": -2, "chaotic": -2,
    "disorganised": -2, "disorganized": -2, "vague": -2, "unclear": -2, "exhausting": -2, "struggled": -2,
    "struggle": -2, "painful": -2, "overwhelming": -2, "harsh": -2,
    "hard": -1, "harder": -1, "difficult": -1, "late": -1, "changing": -1, "long": -1, "tough": -1, "lost": -1,
}
# Multi-word opinions single words miss ("well" alone is too often filler: "if you know it well").
PHRASES: dict[str, float] = {"too much": -2, "a lot of work": -1.5, "not worth": -3, "highly recommend": 3,
                             "taught me": 2, "hard to follow": -2, "kept changing": -1, "very well": 1}
NEGATORS = {"not", "never", "no", "dont", "don't", "didnt", "didn't", "isnt", "isn't", "wasnt", "wasn't",
            "without", "hardly", "nothing"}
BOOSTERS = {"very": 0.3, "really": 0.3, "extremely": 0.5, "super": 0.3, "so": 0.2, "quite": 0.1, "too": 0.3}

THEMES: dict[str, list[str]] = {
    "workload": [r"workload", r"\bhours?\b", r"\b(a|per) week\b", r"\bweekly\b", r"weekends?", r"\bheavy\b",
                 r"overloaded", r"manageable", r"\bta job\b", r"alongside", r"time[- ]consuming"],
    "exams": [r"\bexams?\b", r"mid-?term", r"mid-?sem", r"end-?sem", r"\bfinals?\b", r"quiz",
              r"\b(question|practice|exam|past|previous)( year)? papers?\b"],
    "assignments and projects": [r"assignment", r"\bprojects?\b", r"deadline", r"\blabs?\b", r"homework", r"\bspecs?\b"],
    "teaching": [r"lecture", r"explain", r"instructor", r"professor", r"\bprof\b", r"slides", r"\btas\b",
                 r"\bta (sessions?|hours)\b", r"\bthe ta\b", r"office hours", r"teach", r"taught"],
    "grading": [r"grading", r"\bgrades?\b", r"\bmarks\b", r"evaluation", r"graded"],
    "prerequisites": [r"prerequisite", r"background", r"before joining", r"brush up", r"assumed",
                      r"linear algebra", r"\bpython\b", r"numpy", r"before the course", r"revise"],
    "pace and content": [r"\bpace\b", r"rushed", r"crammed", r"content", r"syllabus", r"topics?", r"organi[sz]ed"],
}
_THEME_RES = {theme: re.compile("|".join(patterns)) for theme, patterns in THEMES.items()}
_ADVICE_START = re.compile(r"^(start|attend|brush|revise|read|form|do not|don't|dont|avoid|make sure|take|practi[cs]e|"
                           r"prepare|expect|plan|keep|ask|go to|join|try)\b")
_TOKEN = re.compile(r"[a-z']+|\+?\d+\+?")
_SENTENCE = re.compile(r"(?<=[.!?])\s+|\n+")


def sentences(text: str) -> list[str]:
    return [s.strip() for s in _SENTENCE.split(text) if s.strip()]


def lexicon_score(sentence: str) -> float:
    """The word-list score: -1 (very negative) to +1 (very positive)."""
    lowered = sentence.lower()
    tokens = _TOKEN.findall(lowered)
    weights = []
    for i, tok in enumerate(tokens):
        value = WORDS.get(tok, 0.0)
        if not value:
            weights.append(0.0)
            continue
        if i > 0 and tokens[i - 1] in BOOSTERS:
            value += math.copysign(BOOSTERS[tokens[i - 1]] * abs(value), value)
        if any(t in NEGATORS for t in tokens[max(0, i - 3):i]):
            value *= -0.75
        weights.append(value)
    # "Great content, but the workload is heavy": what follows "but" counts a little more. A milder
    # tilt than VADER's 0.5/1.5, so a sentence praising one thing and criticising another stays mixed.
    if "but" in tokens:
        cut = tokens.index("but")
        weights = [w * (0.75 if i < cut else 1.25) for i, w in enumerate(weights)]
    total = sum(weights) + sum(v for phrase, v in PHRASES.items() if phrase in lowered)
    return total / math.sqrt(total * total + 15) if total else 0.0


score = lexicon_score   # synchronous scoring for scripts and tests; the API uses sentiment_backends


def themes(sentence: str) -> list[str]:
    lowered = sentence.lower()
    return [theme for theme, pattern in _THEME_RES.items() if pattern.search(lowered)]


def is_advice(sentence: str) -> bool:
    lowered = sentence.lower().strip()
    return bool(_ADVICE_START.match(lowered)) or " should " in f" {lowered} " or "recommend" in lowered


POSITIVE_CUTOFF = 0.25


def label(value: float) -> str:
    """Strictly beyond ±0.25 counts as an opinion; a single mild word stays "mixed"."""
    return "positive" if value > POSITIVE_CUTOFF else "negative" if value < -POSITIVE_CUTOFF else "mixed"
