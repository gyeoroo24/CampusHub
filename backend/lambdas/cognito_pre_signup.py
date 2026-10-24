"""Cognito pre sign-up trigger (FR-1): only IISc email addresses can create an account.

Attach this as the user pool's "Pre sign-up" Lambda trigger. Accepted: anything ending in
iisc.ac.in or a subdomain of it (alum.iisc.ac.in, vendor.iisc.ac.in, ...), any letter case.
Uses the same rule as the database's iisc_email domain and app/auth.py.

It deliberately does NOT set autoConfirmUser or autoVerifyEmail: Cognito must email the
person a verification code, so the backend can trust the email_verified claim.
"""
import re

# ASCII only and matched against the whole string, so lookalike letters and a trailing
# newline are rejected.
IISC_EMAIL = re.compile(r"[^@\s]+@([a-z0-9-]+\.)*iisc\.ac\.in", re.IGNORECASE | re.ASCII)


def handler(event, context):
    email = event.get("request", {}).get("userAttributes", {}).get("email", "")
    if IISC_EMAIL.fullmatch(email) is None:
        # Cognito shows this message to the person signing up.
        raise Exception("Only IISc email addresses (ending in iisc.ac.in) can sign up for CampusHub.")
    return event
