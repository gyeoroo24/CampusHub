"""Who is calling?

Guests send no token and get read-only access (FR-1). Signed-in users send their Cognito
ID token as "Authorization: Bearer <id_token>". On a user's first request we create their
row in `users` (Cognito has already checked the IISc email at sign-up; we check again).

Only verified emails are trusted: Cognito marks the email verified once the person types in
the code it emailed them (at sign-up, and again before an email change takes effect). Without
that check, someone could change their Cognito email to a colleague's before their first API
call and get an account under the colleague's address.

Roles are NOT taken from the token's Cognito groups: admin comes from users.base_role and
moderator rights from moderator_assignments, read fresh on every request, so a revoked
moderator's next call is rejected (FR-3).
"""
import asyncio
import logging
import re
from dataclasses import dataclass
from uuid import UUID

import asyncpg
import jwt
from fastapi import Depends, HTTPException, Request

from .config import get_settings
from .db import get_conn

log = logging.getLogger("campushub.auth")

# Same rule as the database's iisc_email domain and the Cognito pre-sign-up Lambda.
# ASCII only, so Unicode lookalikes (e.g. the Kelvin sign for "k") don't pass; use fullmatch().
IISC_EMAIL = re.compile(r"[^@\s]+@([a-z0-9-]+\.)*iisc\.ac\.in", re.IGNORECASE | re.ASCII)

# Dev sign-in (X-Dev-User) is only honoured from this machine; "testclient" is FastAPI's TestClient.
_LOCAL_CLIENTS = {"127.0.0.1", "::1", "localhost", "testclient"}


def is_iisc_email(email: str) -> bool:
    return IISC_EMAIL.fullmatch(email) is not None


@dataclass(frozen=True)
class CurrentUser:
    id: UUID
    email: str
    name: str
    is_admin: bool


_jwks_client: jwt.PyJWKClient | None = None


def _get_jwks_client() -> jwt.PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        s = get_settings()
        url = (f"https://cognito-idp.{s.cognito_region}.amazonaws.com/"
               f"{s.cognito_user_pool_id}/.well-known/jwks.json")
        _jwks_client = jwt.PyJWKClient(url, cache_keys=True, timeout=s.jwks_timeout_seconds)
    return _jwks_client


def verify_cognito_id_token(token: str) -> dict:
    """Check signature, expiry, issuer and audience of a Cognito ID token; return its claims."""
    s = get_settings()
    issuer = f"https://cognito-idp.{s.cognito_region}.amazonaws.com/{s.cognito_user_pool_id}"
    try:
        signing_key = _get_jwks_client().get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            audience=s.cognito_app_client_id,
            issuer=issuer,
            options={"require": ["exp", "iat", "sub", "token_use"]},
        )
    except jwt.PyJWKClientConnectionError as exc:
        # Our problem, not the user's: Cognito's signing keys couldn't be downloaded.
        log.exception("Could not fetch Cognito signing keys")
        raise HTTPException(503, "Sign-in is temporarily unavailable. Try again in a moment.") from exc
    except jwt.PyJWTError as exc:
        raise HTTPException(401, "Your sign-in is invalid or has expired. Sign in again.",
                            headers={"WWW-Authenticate": "Bearer"}) from exc
    if claims.get("token_use") != "id":
        raise HTTPException(401, "Send the Cognito ID token, not the access token.",
                            headers={"WWW-Authenticate": "Bearer"})
    return claims


def _dev_identity(request: Request) -> dict | None:
    email = request.headers.get("x-dev-user")
    if not email:
        return None
    if request.client is None or request.client.host not in _LOCAL_CLIENTS:
        raise HTTPException(403, "Dev sign-in only works from the machine the API runs on.")
    return {"sub": f"dev|{email.strip().lower()}", "email": email.strip(), "email_verified": True,
            "name": request.headers.get("x-dev-name") or email.split("@")[0]}


async def _identity_from_request(request: Request) -> dict | None:
    if get_settings().auth_mode == "dev":
        return _dev_identity(request)

    header = request.headers.get("authorization")
    if not header:
        return None
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(401, "Use the header 'Authorization: Bearer <ID token>'.",
                            headers={"WWW-Authenticate": "Bearer"})
    # The first call in a container downloads Cognito's public keys, so run it off the event loop.
    return await asyncio.to_thread(verify_cognito_id_token, token.strip())


_USER_COLUMNS = "id, email::text AS email, name, base_role::text AS base_role, is_active"


def _email_verified(identity: dict) -> bool:
    return identity.get("email_verified") in (True, "true")


async def _create_user(conn: asyncpg.Connection, sub: str, email: str, name: str) -> asyncpg.Record:
    """First sign-in: create the row, or relink it if this verified email already has one."""
    async with conn.transaction():
        # No conflict target: a parallel first request (same sub) or an existing row with this
        # email both end up here without raising.
        row = await conn.fetchrow(
            f"""INSERT INTO users (cognito_sub, email, name) VALUES ($1, $2, $3)
                ON CONFLICT DO NOTHING RETURNING {_USER_COLUMNS}""", sub, email, name)
        if row is None:
            row = await conn.fetchrow(f"SELECT {_USER_COLUMNS} FROM users WHERE cognito_sub = $1", sub)
        if row is None:
            # The email belongs to an older Cognito account (the person re-created their account,
            # or the user pool was rebuilt). The email is verified, so this is the same person.
            row = await conn.fetchrow(
                f"UPDATE users SET cognito_sub = $1 WHERE email = $2 RETURNING {_USER_COLUMNS}", sub, email)
            if row is not None:
                log.warning("Relinked user %s (%s) to a new Cognito account", row["id"], email)
    if row is None:
        raise HTTPException(409, "Couldn't create your account. Try signing in again.")
    return row


async def _load_or_create_user(conn: asyncpg.Connection, identity: dict) -> CurrentUser:
    row = await conn.fetchrow(f"SELECT {_USER_COLUMNS} FROM users WHERE cognito_sub = $1", identity["sub"])
    if row is None:
        email = (identity.get("email") or "").strip()
        if not is_iisc_email(email):
            raise HTTPException(403, "Only IISc email addresses (ending in iisc.ac.in) can use CampusHub.")
        if not _email_verified(identity):
            raise HTTPException(403, "Verify your email address first: enter the code we emailed you, "
                                     "then sign in again.")
        name = (identity.get("name") or email.split("@")[0]).strip()[:100]
        row = await _create_user(conn, identity["sub"], email, name)
    if not row["is_active"]:
        raise HTTPException(403, "This account has been deactivated.")
    return CurrentUser(id=row["id"], email=row["email"], name=row["name"], is_admin=row["base_role"] == "admin")


async def optional_user(request: Request, conn: asyncpg.Connection = Depends(get_conn)) -> CurrentUser | None:
    """The caller, or None for a guest. Every route depends on this (see main.py), so a bad or
    expired token is rejected everywhere, including pages guests can read."""
    identity = await _identity_from_request(request)
    if identity is None:
        return None
    return await _load_or_create_user(conn, identity)


async def current_user(user: CurrentUser | None = Depends(optional_user)) -> CurrentUser:
    """The caller; guests get 401."""
    if user is None:
        raise HTTPException(401, "Sign in to do this.", headers={"WWW-Authenticate": "Bearer"})
    return user
