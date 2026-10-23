"""Turn database constraint errors into clear HTTP responses.

Routes check permissions and existence themselves; these handlers are the safety net
for rules the database enforces (unique names, CHECK constraints, foreign keys).
"""
import asyncpg
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


def _body(message: str, exc: asyncpg.PostgresError) -> dict:
    body = {"detail": message}
    constraint = getattr(exc, "constraint_name", None)
    if constraint:
        body["constraint"] = constraint
    return body


def install_error_handlers(app: FastAPI) -> None:
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
