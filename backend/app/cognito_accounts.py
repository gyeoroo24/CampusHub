"""Is a person's sign-in account still usable in the Cognito user pool?

The users table keeps a row for everyone who has ever signed in. If the Cognito account is deleted or
disabled, that row stays, so a role could be granted to someone who can no longer sign in. Checked when a
moderator role is granted. The pool signs people in by email, so Cognito's username is the user's sub.
"""
import asyncio

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from .config import get_settings


class AccountCheckUnavailable(Exception):
    """Cognito couldn't be asked. The grant goes ahead and the failure is logged (routers/moderators.py)."""


def _admin_get_user(pool_id: str, region: str, username: str) -> dict | None:
    client = boto3.client("cognito-idp", region_name=region)
    try:
        return client.admin_get_user(UserPoolId=pool_id, Username=username)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "UserNotFoundException":
            return None
        raise AccountCheckUnavailable(str(exc)) from exc
    except BotoCoreError as exc:   # no route to Cognito, timeouts, missing credentials
        raise AccountCheckUnavailable(str(exc)) from exc


async def signin_account_problem(cognito_sub: str) -> str | None:
    """None if the person can sign in; otherwise the reason to show the admin."""
    s = get_settings()
    if s.auth_mode != "cognito":
        return None   # dev sign-in has no Cognito accounts
    user = await asyncio.to_thread(_admin_get_user, s.cognito_user_pool_id, s.cognito_region, cognito_sub)
    if user is None:
        return "This person's sign-in account no longer exists, so they can't use a moderator role."
    if not user.get("Enabled", False) or user.get("UserStatus") != "CONFIRMED":
        return "This person's sign-in account is disabled or unconfirmed, so they can't use a moderator role."
    return None
