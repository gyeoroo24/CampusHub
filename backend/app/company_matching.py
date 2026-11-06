"""Which companies are probably the same one under slightly different names.

Placement sheets name a company however the placement cell typed it that day: "Accenture",
"Accenture [Mock Assessment]", "Accenture (Final Assessment)", "oserve.ai", "Observe AI". Each name
becomes its own company, so one company's records are split across several pages. This module groups
names that only differ by bracketed notes, assessment/round words, a web domain ending, punctuation,
spacing or a small typo, so a moderator can review the groups and merge them (POST
/placement/companies/merge). Nothing is merged without that review.
"""
import re
from difflib import SequenceMatcher

# Words that describe the hiring step rather than the company.
_STEP_WORDS = {
    "mock", "assessment", "assessments", "final", "test", "tests", "oa", "online", "interview", "interviews",
    "round", "rounds", "ppt", "drive", "hiring", "internship", "intern", "fte", "offline", "coding",
    "technical", "aptitude", "written", "exam", "shortlist", "shortlisted", "results", "result",
}
# Legal-form endings that don't tell companies apart.
_LEGAL_WORDS = {"pvt", "private", "ltd", "limited", "inc", "llc", "llp", "corp", "corporation", "co", "plc", "gmbh", "india"}
_DOMAIN_ENDINGS = r"\.(?:ai|com|io|in|co|org|net|tech|app|dev|so)\b"
# Above this, two different keys are treated as a typo of each other ("oserve" / "observe").
SIMILARITY = 0.88
# Short keys are compared exactly only: "ibm" and "ibx" aren't the same company.
MIN_FUZZY_LENGTH = 5


def match_keys(name: str) -> set[str]:
    """The parts of a company name that identify the company: lower case, without bracketed notes, step
    words, legal endings, punctuation or spaces. Two keys: with a domain ending dropped ("oserve.ai" ->
    "oserve") and kept as a word ("oserveai"), so it matches both "Oserve" and "Oserve AI"."""
    text = name.lower()
    text = re.sub(r"[\[({].*?[\])}]", " ", text)          # "[Mock Assessment]", "(Final)"
    text = re.sub(r"\s[-–—:|/]\s.*$", " ", text)           # "Accenture - Mock assessment"
    keys = set()
    for variant in (re.sub(_DOMAIN_ENDINGS, " ", text), text):
        words = re.findall(r"[a-z0-9&]+", variant)
        kept = [w for w in words if w not in _STEP_WORDS and w not in _LEGAL_WORDS]
        if key := "".join(kept or words):
            keys.add(key)
    return keys


def display_name(name: str) -> str:
    """A clean name to suggest for a group: the name without bracketed notes or a trailing step."""
    text = re.sub(r"[\[({].*?[\])}]", " ", name)
    text = re.sub(r"\s[-–—:|/]\s.*$", " ", text)
    words = text.split()
    while words and words[-1].lower().strip(".,") in _STEP_WORDS:
        words.pop()
    return " ".join(words) or name.strip()


def _similar_key(a: str, b: str) -> bool:
    if a == b:
        return True
    if min(len(a), len(b)) < MIN_FUZZY_LENGTH:
        return False
    return SequenceMatcher(None, a, b).ratio() >= SIMILARITY


def _similar(a: set[str], b: set[str]) -> bool:
    return any(_similar_key(x, y) for x in a for y in b)


def group_similar(names: dict) -> list[list]:
    """Groups of ids (2 or more) whose names are probably the same company. [names] maps id -> name.
    Each group is in the order the ids were given."""
    keys = {i: match_keys(n) for i, n in names.items()}
    ids = list(names)
    parent = {i: i for i in ids}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for x, a in enumerate(ids):
        for b in ids[x + 1:]:
            if keys[a] and keys[b] and _similar(keys[a], keys[b]):
                parent[find(b)] = find(a)
    groups: dict = {}
    for i in ids:
        groups.setdefault(find(i), []).append(i)
    return [g for g in groups.values() if len(g) > 1]


def suggested_name(names: list[str], weights: list[int] | None = None) -> str:
    """The name to suggest for a merged group: the clean name used by the most records (weights, one per
    name), then the most common, then the shortest."""
    cleaned = [display_name(n) for n in names]
    weights = weights or [0] * len(names)
    score = {c: sum(w for c2, w in zip(cleaned, weights) if c2 == c) for c in cleaned}
    return min(cleaned, key=lambda c: (-score[c], -cleaned.count(c), len(c), c.lower()))
