"""Small shared pieces: pagination, reference models, text and id types, and the PATCH helper."""
from dataclasses import dataclass
from typing import Annotated, Generic, TypeVar
from uuid import UUID

from fastapi import HTTPException, Query
from pydantic import AfterValidator, BaseModel, Field, StringConstraints

T = TypeVar("T")

# Category ids are 32-bit integers in the database.
MAX_INT_ID = 2_147_483_647
CategoryId = Annotated[int, Field(ge=1, le=MAX_INT_ID)]


def _one_line(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise ValueError("must be a single line")
    return value


def text(max_length: int, min_length: int = 1, single_line: bool = False):
    """A string with surrounding whitespace removed; by default it must not be blank.

    single_line: for titles and names, which are shown on one line, reject embedded line breaks.
    """
    stripped = Annotated[str, StringConstraints(strip_whitespace=True, min_length=min_length, max_length=max_length)]
    return Annotated[stripped, AfterValidator(_one_line)] if single_line else stripped


def search_text(q: str | None) -> str | None:
    """A search box sends q= when it's empty; treat that as no search."""
    if q is None or not q.strip():
        return None
    return q.strip()


def like_pattern(q: str) -> str:
    """Escape LIKE wildcards so a search for "50%" matches the text "50%"; use with ESCAPE '\\'."""
    return q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


class Page(BaseModel, Generic[T]):
    items: list[T]
    limit: int
    offset: int
    has_more: bool


@dataclass(frozen=True)
class PageParams:
    limit: int
    offset: int


def page_params(
    limit: int = Query(20, ge=1, le=50, description="Items per page (max 50)"),
    offset: int = Query(0, ge=0, le=10_000, description="Items to skip"),
) -> PageParams:
    return PageParams(limit=limit, offset=offset)


def make_page(rows: list, params: PageParams, convert) -> dict:
    """Queries fetch limit + 1 rows; the extra row only tells us whether another page exists."""
    has_more = len(rows) > params.limit
    return {
        "items": [convert(r) for r in rows[: params.limit]],
        "limit": params.limit,
        "offset": params.offset,
        "has_more": has_more,
    }


class UserRef(BaseModel):
    id: UUID
    name: str


class CategoryRef(BaseModel):
    id: int
    name: str


class Contact(BaseModel):
    """How to reach a seller or reporter (scenario 1). Shown to signed-in users only."""
    email: str
    phone: str | None


class Photo(BaseModel):
    s3_key: str
    url: str
    sort_order: int


def set_clause(changes: dict, start: int = 1) -> tuple[str, list]:
    """Build "col = $n, ..." for a PATCH. Column names come from Pydantic field names, never user input."""
    if not changes:
        raise HTTPException(422, "Send at least one field to change.")
    cols = list(changes)
    sql = ", ".join(f"{col} = ${i}" for i, col in enumerate(cols, start))
    return sql, [changes[c] for c in cols]


def not_found(what: str) -> HTTPException:
    return HTTPException(404, f"{what} not found.")


def forbidden(message: str = "You don't have permission to do this.") -> HTTPException:
    return HTTPException(403, message)
