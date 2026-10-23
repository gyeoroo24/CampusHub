"""Who is calling?

Guests send no token and get read-only access (FR-1). Signed-in users send their Cognito
ID token as "Authorization: Bearer <id_token>". On a user's first request we create their
row in `users` (Cognito has already checked the IISc email at sign-up; we check again).

Roles are NOT taken from the token's Cognito groups: admin comes from users.base_role and
moderator rights from moderator_assignments, read fresh on every request, so a revoked
moderator's next call is rejected (FR-3).
"""
import asyncio
import re
from dataclasses import dataclass
from uuid import UUID

import asyncpg
import jwt
from fastapi import Depends, HTTPException, Request

from .config import get_settings
from .db import get_conn

IISC_EMAIL = re.compile(r"^[^@\s]+@([a-z0-9-]+\.)*iisc\.ac\.in$", re.IGNORECASE)


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
        _jwks_client = jwt.PyJWKClient(url, cache_keys=True)
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
    except jwt.PyJWTError as exc:
        raise HTTPException(401, "Your sign-in is invalid or has expired. Sign in again.",
                            headers={"WWW-Authenticate": "Bearer"}) from exc
    if claims.get("token_use") != "id":
        raise HTTPException(401, "Send the Cognito ID token, not the access token.",
                            headers={"WWW-Authenticate": "Bearer"})
    return claims


async def _identity_from_request(request: Request) -> dict | None:
    s = get_settings()
    if s.auth_mode == "dev":
        email = request.headers.get("x-dev-user")
        if not email:
            return None
        return {"sub": f"dev|{email.strip().lower()}", "email": email.strip(),
                "name": request.headers.get("x-dev-name") or email.split("@")[0]}

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


async def _load_or_create_user(conn: asyncpg.Connection, identity: dict) -> CurrentUser:
    row = await conn.fetchrow(f"SELECT {_USER_COLUMNS} FROM users WHERE cognito_sub = $1", identity["sub"])
    if row is None:
        email = (identity.get("email") or "").strip()
        if not IISC_EMAIL.match(email):
            raise HTTPException(403, "Only IISc email addresses (ending in iisc.ac.in) can use CampusHub.")
        name = (identity.get("name") or email.split("@")[0]).strip()[:100]
        try:
            row = await conn.fetchrow(
                f"""INSERT INTO users (cognito_sub, email, name) VALUES ($1, $2, $3)
                    ON CONFLICT (cognito_sub) DO NOTHING RETURNING {_USER_COLUMNS}""",
                identity["sub"], email, name)
        except asyncpg.UniqueViolationError as exc:
            raise HTTPException(409, "Another account already uses this email address.") from exc
        if row is None:  # created by a parallel request a moment ago
            row = await conn.fetchrow(f"SELECT {_USER_COLUMNS} FROM users WHERE cognito_sub = $1", identity["sub"])
    if not row["is_active"]:
        raise HTTPException(403, "This account has been deactivated.")
    return CurrentUser(id=row["id"], email=row["email"], name=row["name"], is_admin=row["base_role"] == "admin")


async def optional_user(request: Request, conn: asyncpg.Connection = Depends(get_conn)) -> CurrentUser | None:
    """The caller, or None for a guest."""
    identity = await _identity_from_request(request)
    if identity is None:
        return None
    return await _load_or_create_user(conn, identity)


async def current_user(user: CurrentUser | None = Depends(optional_user)) -> CurrentUser:
    """The caller; guests get 401."""
    if user is None:
        raise HTTPException(401, "Sign in to do this.", headers={"WWW-Authenticate": "Bearer"})
    return user
