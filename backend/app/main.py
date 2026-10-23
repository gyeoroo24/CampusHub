"""CampusHub API.

Local:   uvicorn app.main:app --reload --env-file .env   (docs at http://localhost:8000/docs)
Lambda:  handler = app.main.handler           (API Gateway -> Mangum -> FastAPI)
EC2:     uvicorn app.main:app --host 0.0.0.0  (same code, for the Lambda-vs-EC2 comparison)
"""
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum

from .config import get_settings
from .db import close_pool
from .errors import install_error_handlers
from .routers import academic, categories, forums, listings, lost_found, moderators, notifications, reports, uploads, users

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield
    await close_pool()


def create_app() -> FastAPI:
    settings = get_settings()
    if settings.auth_mode == "dev" and os.environ.get("AWS_LAMBDA_FUNCTION_NAME"):
        raise RuntimeError("CAMPUSHUB_AUTH_MODE=dev is for local development only; use cognito in AWS.")

    app = FastAPI(
        title="CampusHub API",
        version="0.1.0",
        description="Backend for CampusHub, the IISc student community platform (DS252, team Order of Phoenix). "
                    "Guests can read; signed-in users send their Cognito ID token as a Bearer token.",
        lifespan=lifespan,
    )
    app.add_middleware(CORSMiddleware, allow_origins=settings.cors_allow_origins,
                       allow_methods=["*"], allow_headers=["*"])
    install_error_handlers(app)
    for module in (users, moderators, uploads, categories, listings, academic, forums, reports, notifications):
        app.include_router(module.router, prefix=settings.api_prefix)
    app.include_router(lost_found.lost_router, prefix=settings.api_prefix)
    app.include_router(lost_found.found_router, prefix=settings.api_prefix)
    return app


app = create_app()

# Lambda entry point. Lifespan is off: the DB pool is created on first use and reused
# across invocations of the same warm container.
handler = Mangum(app, lifespan="off")
