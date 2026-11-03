"""CampusHub API.

Local:   uvicorn app.main:app --reload --env-file .env   (docs at http://localhost:8000/docs)
Lambda:  handler = app.main.handler           (API Gateway -> Mangum -> FastAPI)
EC2:     uvicorn app.main:app --host 0.0.0.0  (same code, for the Lambda-vs-EC2 comparison)
"""
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum

from .auth import optional_user
from .config import get_settings, in_lambda
from .db import close_pool
from .errors import install_error_handlers
from .jobs import meal_alert_loop
from .routers import (academic, auth_otp, campus_services, categories, chat, events, forums, listings, lost_found,
                      mess, moderators, notifications, placement, reports, saved_searches, seller_trust, survival_guide,
                      uploads, users, wanted)

logging.basicConfig(level=logging.INFO)
# Lambda installs its own root handler before our code runs, which makes basicConfig a no-op.
logging.getLogger().setLevel(logging.INFO)


@asynccontextmanager
async def lifespan(_: FastAPI):
    every = get_settings().meal_alert_poll_seconds
    checker = asyncio.create_task(meal_alert_loop(every)) if every > 0 and not in_lambda() else None
    yield
    if checker:
        checker.cancel()
    await close_pool()


def _check_settings() -> None:
    s = get_settings()
    if s.auth_mode == "dev":
        if in_lambda():
            raise RuntimeError("CAMPUSHUB_AUTH_MODE=dev is for local development only; use cognito in AWS.")
        if not s.allow_dev_auth:
            raise RuntimeError("CAMPUSHUB_AUTH_MODE=dev lets anyone act as any user. To use it on your own "
                               "machine, also set CAMPUSHUB_ALLOW_DEV_AUTH=true. Never set either on a server.")
    if s.cdn_base_url and not (s.cdn_key_pair_id and s.cdn_private_key):
        raise RuntimeError("CAMPUSHUB_CDN_BASE_URL needs CAMPUSHUB_CDN_KEY_PAIR_ID and CAMPUSHUB_CDN_PRIVATE_KEY "
                           "so file links can be signed and expire.")


def _add_sign_in_to_docs(app: FastAPI) -> None:
    """Give Swagger an Authorize button: the dev header locally, the Cognito ID token otherwise."""
    from fastapi.openapi.utils import get_openapi

    def openapi() -> dict:
        if app.openapi_schema:
            return app.openapi_schema
        schema = get_openapi(title=app.title, version=app.version, description=app.description, routes=app.routes)
        settings = get_settings()
        schemes = schema.setdefault("components", {}).setdefault("securitySchemes", {})
        if settings.auth_mode == "dev":
            schemes["signIn"] = {"type": "apiKey", "in": "header", "name": "X-Dev-User",
                                 "description": "Local testing: any IISc email, e.g. asha@iisc.ac.in"}
        else:
            schemes["signIn"] = {"type": "http", "scheme": "bearer", "bearerFormat": "JWT",
                                 "description": "Cognito ID token"}
        schema["security"] = [{"signIn": []}, {}]   # signed in, or a guest
        if settings.auth_mode == "dev" and settings.dev_auth_key:
            schemes["devKey"] = {"type": "apiKey", "in": "header", "name": "X-Dev-Key",
                                 "description": "Needed from other machines on the network; ask whoever runs the server"}
            schema["security"].insert(0, {"signIn": [], "devKey": []})
        app.openapi_schema = schema
        return schema
    app.openapi = openapi


def create_app() -> FastAPI:
    _check_settings()
    settings = get_settings()
    docs = settings.docs_enabled
    app = FastAPI(
        title="CampusHub API",
        version="0.1.0",
        description="Backend for CampusHub, the IISc student community platform (DS252, team Order of Phoenix). "
                    "Guests can read; signed-in users send their Cognito ID token as a Bearer token.",
        lifespan=lifespan,
        docs_url="/docs" if docs else None,
        redoc_url="/redoc" if docs else None,
        openapi_url="/openapi.json" if docs else None,
    )
    app.add_middleware(CORSMiddleware, allow_origins=settings.cors_allow_origins,
                       allow_methods=["*"], allow_headers=["*"])
    install_error_handlers(app)
    # Every route checks the caller's token, even ones guests can use, so a bad or expired token
    # always gets 401. Routes that need the user reuse the same (cached) result.
    checked = [Depends(optional_user)]
    for module in (users, moderators, uploads, categories, listings, wanted, academic, survival_guide, forums, reports,
                   notifications, saved_searches, campus_services, auth_otp, chat, seller_trust, placement, events, mess):
        app.include_router(module.router, prefix=settings.api_prefix, dependencies=checked)
    app.include_router(listings.watch_router, prefix=settings.api_prefix, dependencies=checked)
    app.include_router(lost_found.lost_router, prefix=settings.api_prefix, dependencies=checked)
    app.include_router(lost_found.found_router, prefix=settings.api_prefix, dependencies=checked)
    _add_sign_in_to_docs(app)
    return app


app = create_app()

# Lambda entry point. Lifespan is off: the DB pool is created on first use and reused
# across invocations of the same warm container.
handler = Mangum(app, lifespan="off")
