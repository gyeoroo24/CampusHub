"""Sign-in OTP email for the local dev auth flow (see app/otp.py). No-op (404) outside dev mode:
Cognito already emails and verifies its own code at sign-up in production.
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..auth import is_iisc_email
from ..common import text
from ..config import get_settings
from .. import otp

router = APIRouter(prefix="/auth/otp", tags=["Dev sign-in"])


def _require_dev_mode() -> None:
    if get_settings().auth_mode != "dev":
        raise HTTPException(404, "Not available: this server signs in through Cognito.")


class OtpRequest(BaseModel):
    email: text(254)


class OtpVerify(BaseModel):
    email: text(254)
    otp: text(6, min_length=6)


@router.post("/request", status_code=204, summary="Email a sign-in code")
async def request_otp(body: OtpRequest) -> None:
    _require_dev_mode()
    email = body.email.strip().lower()
    if not is_iisc_email(email):
        raise HTTPException(400, "Only IISc email addresses (ending in iisc.ac.in) are accepted.")
    otp.request_otp(email)


@router.post("/verify", status_code=204, summary="Check a sign-in code")
async def verify_otp(body: OtpVerify) -> None:
    _require_dev_mode()
    otp.verify_otp(body.email, body.otp)
