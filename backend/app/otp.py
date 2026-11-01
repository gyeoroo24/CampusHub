"""Email OTP codes for the dev sign-in flow (auth_mode="dev" only).

Cognito handles email verification itself in production (see auth.py); this module exists so
local sign-in also asks for a real code instead of accepting any 6 digits. Codes live in process
memory — fine for a single dev server, and nothing worth persisting across a restart.
"""
import hashlib
import logging
import secrets
import smtplib
import time
from dataclasses import dataclass
from email.message import EmailMessage

from fastapi import HTTPException

from .config import get_settings

log = logging.getLogger("campushub.otp")


@dataclass
class _Entry:
    code_hash: str
    expires_at: float
    attempts: int
    sent_at: float


_store: dict[str, _Entry] = {}


def _hash(email: str, code: str) -> str:
    return hashlib.sha256(f"{email}:{code}".encode()).hexdigest()


def _send_email(to: str, code: str) -> None:
    s = get_settings()
    if not s.smtp_host:
        # No mail server configured: this *is* the delivery mechanism for local dev, not a
        # fallback hack, so it's logged at a level that shows up with uvicorn's default config.
        log.warning("SMTP not configured — CampusHub sign-in code for %s is %s (valid %d min)",
                    to, code, s.otp_ttl_seconds // 60)
        return

    msg = EmailMessage()
    msg["Subject"] = f"Your CampusHub sign-in code: {code}"
    msg["From"] = s.smtp_from
    msg["To"] = to
    msg.set_content(
        f"Your CampusHub sign-in code is {code}\n\n"
        f"It expires in {s.otp_ttl_seconds // 60} minutes. If you didn't request this, ignore this email."
    )
    try:
        with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=10) as smtp:
            smtp.starttls()
            if s.smtp_user and s.smtp_password:
                smtp.login(s.smtp_user, s.smtp_password)
            smtp.send_message(msg)
    except (smtplib.SMTPException, OSError):
        log.exception("Failed to send OTP email to %s", to)
        raise HTTPException(503, "Couldn't send the sign-in email right now. Try again in a moment.")


def _send_sms(to: str, code: str) -> None:
    """No SMS provider is set up yet (Amazon SNS would be the AWS choice), so the code is logged,
    the same way sign-in codes are when SMTP isn't configured."""
    log.warning("No SMS provider — CampusHub phone verification code for %s is %s (valid %d min)",
                to, code, get_settings().otp_ttl_seconds // 60)


def request_phone_otp(user_id: str, phone: str) -> None:
    """A code to prove the user owns [phone] before it goes on their profile."""
    request_otp(f"phone:{user_id}:{phone}", send=lambda _key, code: _send_sms(phone, code))


def verify_phone_otp(user_id: str, phone: str, code: str) -> bool:
    return verify_otp(f"phone:{user_id}:{phone}", code)


def request_otp(email: str, send=None) -> None:
    """[email] is the key codes are kept under; [send] delivers the code (email by default)."""
    email = email.strip().lower()
    s = get_settings()
    now = time.monotonic()
    existing = _store.get(email)
    if existing and now - existing.sent_at < s.otp_resend_cooldown_seconds:
        wait = int(s.otp_resend_cooldown_seconds - (now - existing.sent_at))
        raise HTTPException(429, f"Wait {wait}s before requesting another code.")

    code = f"{secrets.randbelow(1_000_000):06d}"
    _store[email] = _Entry(code_hash=_hash(email, code), expires_at=now + s.otp_ttl_seconds,
                           attempts=0, sent_at=now)
    (send or _send_email)(email, code)


def verify_otp(email: str, code: str) -> bool:
    email = email.strip().lower()
    s = get_settings()
    entry = _store.get(email)
    if entry is None:
        raise HTTPException(400, "Request a new code first.")
    if time.monotonic() > entry.expires_at:
        del _store[email]
        raise HTTPException(400, "That code expired. Request a new one.")
    if entry.attempts >= s.otp_max_attempts:
        del _store[email]
        raise HTTPException(429, "Too many incorrect attempts. Request a new code.")

    if not secrets.compare_digest(entry.code_hash, _hash(email, code.strip())):
        entry.attempts += 1
        raise HTTPException(401, "Incorrect code.")

    del _store[email]
    return True
