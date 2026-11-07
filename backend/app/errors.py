"""Turn database constraint errors into clear HTTP responses.

Routes check permissions and existence themselves; these handlers are the safety net
for rules the database enforces (unique names, CHECK constraints, foreign keys).
"""
import logging
import math

import asyncpg
from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

log = logging.getLogger(__name__)


def _body(message: str, exc: asyncpg.PostgresError) -> dict:
    # The constraint name is internal schema detail: log it for us, don't send it to the client.
    constraint = getattr(exc, "constraint_name", None)
    if constraint:
        log.info("%s: %s (constraint %s)", type(exc).__name__, message, constraint)
    return {"detail": message}


def _json_safe(value):
    """NaN and Infinity aren't valid JSON, so echoing them back in a 422 would crash the response."""
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    return value


def install_error_handlers(app: FastAPI) -> None:
    # Same body as FastAPI's own handler, but a payload like {"price": NaN} gets a 422, not a 500.
    @app.exception_handler(RequestValidationError)
    async def _invalid(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(status_code=422, content={"detail": _json_safe(jsonable_encoder(exc.errors()))})

    @app.exception_handler(asyncpg.exceptions.UniqueViolationError)
    async def _unique(_: Request, exc: asyncpg.PostgresError) -> JSONResponse:
        return JSONResponse(status_code=409, content=_body("This already exists.", exc))

    @app.exception_handler(asyncpg.exceptions.CheckViolationError)
    async def _check(_: Request, exc: asyncpg.PostgresError) -> JSONResponse:
        return JSONResponse(status_code=422, content=_body("A value is not allowed.", exc))

    @app.exception_handler(asyncpg.exceptions.ForeignKeyViolationError)
    async def _fk(_: Request, exc: asyncpg.PostgresError) -> JSONResponse:
        return JSONResponse(status_code=422, content=_body("A referenced item does not exist.", exc))

    @app.exception_handler(asyncpg.exceptions.NotNullViolationError)
    async def _not_null(_: Request, exc: asyncpg.PostgresError) -> JSONResponse:
        return JSONResponse(status_code=422, content=_body("A required value is missing.", exc))

    # Values the database can't store, e.g. an id larger than a 32-bit integer.
    @app.exception_handler(asyncpg.exceptions.DataError)
    async def _data(_: Request, exc: asyncpg.PostgresError) -> JSONResponse:
        return JSONResponse(status_code=422, content=_body("A value is out of range or has the wrong format.", exc))
