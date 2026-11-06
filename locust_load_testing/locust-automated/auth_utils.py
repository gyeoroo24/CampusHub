"""Authentication and JWT utilities for CampusHub performance testing."""
import re
import time
from typing import Dict, Any, Tuple
import jwt
import requests


def sanitize_token(token: str) -> str:
    """Sanitize raw token input from clipboard or user entry.
    
    Handles:
      - Extra spaces, newlines, carriage returns
      - Enclosing single or double quotes
      - "Bearer " or "bearer " prefix
    """
    if not token:
        return ""
    
    clean = token.strip()
    # Strip quotes if wrapped
    if (clean.startswith('"') and clean.endswith('"')) or (clean.startswith("'") and clean.endswith("'")):
        clean = clean[1:-1].strip()
        
    # Remove 'Bearer ' prefix (case insensitive)
    if clean.lower().startswith("bearer "):
        clean = clean[7:].strip()
        
    # Remove internal newlines or tabs from copy-pasting
    clean = "".join(clean.split())
    return clean


def decode_jwt(token: str) -> Dict[str, Any]:
    """Decode Cognito JWT claims without signature verification.
    
    Returns structured dict with expiration status and remaining time.
    """
    clean_token = sanitize_token(token)
    if not clean_token:
        return {
            "valid": False,
            "error": "Empty token",
            "is_expired": True,
            "email": None,
            "sub": None,
            "exp": None,
            "time_left_str": "No token provided",
        }
        
    try:
        # Decode without verifying signature
        claims = jwt.decode(clean_token, options={"verify_signature": False})
        exp = claims.get("exp")
        now = time.time()
        
        email = claims.get("email") or claims.get("cognito:username") or "Unknown"
        sub = claims.get("sub", "")
        
        if exp is None:
            return {
                "valid": True,
                "error": None,
                "is_expired": False,
                "email": email,
                "sub": sub,
                "exp": None,
                "time_left_str": "No expiration claim",
                "claims": claims,
            }
            
        remaining_sec = int(exp - now)
        is_expired = remaining_sec <= 0
        
        if is_expired:
            ago_sec = abs(remaining_sec)
            if ago_sec < 60:
                time_str = f"Expired {ago_sec}s ago"
            elif ago_sec < 3600:
                time_str = f"Expired {ago_sec // 60}m ago"
            else:
                time_str = f"Expired {ago_sec // 3600}h {(ago_sec % 3600) // 60}m ago"
        else:
            if remaining_sec < 60:
                time_str = f"{remaining_sec}s remaining"
            elif remaining_sec < 3600:
                time_str = f"{remaining_sec // 60}m {remaining_sec % 60}s remaining"
            else:
                time_str = f"{remaining_sec // 3600}h {(remaining_sec % 3600) // 60}m remaining"
                
        return {
            "valid": True,
            "error": None,
            "is_expired": is_expired,
            "email": email,
            "sub": sub,
            "exp": exp,
            "remaining_seconds": remaining_sec,
            "time_left_str": time_str,
            "claims": claims,
        }
    except Exception as exc:
        return {
            "valid": False,
            "error": f"Invalid JWT structure: {str(exc)}",
            "is_expired": True,
            "email": None,
            "sub": None,
            "exp": None,
            "time_left_str": "Invalid JWT format",
        }


def test_token_live(host: str, token: str, timeout: float = 6.0) -> Tuple[bool, int, str]:
    """Test Cognito token against live host `/api/v1/me`.
    
    Returns (success: bool, status_code: int, message: str)
    """
    clean_token = sanitize_token(token)
    if not clean_token:
        return False, 0, "No token provided to test"
        
    host_clean = host.strip().rstrip("/")
    if host_clean.endswith("/api/v1"):
        host_clean = host_clean[:-7]
        
    url = f"{host_clean}/api/v1/me"
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {clean_token}",
    }
    
    try:
        resp = requests.get(url, headers=headers, timeout=timeout)
        if resp.status_code == 200:
            data = resp.json()
            email = data.get("email", "Student")
            role = data.get("role", "student")
            is_mod = data.get("is_moderator", False)
            mod_str = " (Moderator)" if is_mod else ""
            return True, 200, f"Token Verified! Logged in as: {email} [{role}]{mod_str}"
        elif resp.status_code == 401:
            return False, 401, "HTTP 401 Unauthorized: Token is expired or rejected by Cognito."
        elif resp.status_code == 403:
            return False, 403, "HTTP 403 Forbidden: Account suspended or access denied."
        elif resp.status_code == 502:
            return False, 502, "HTTP 502 Bad Gateway: ALB cannot reach backend instances."
        else:
            return False, resp.status_code, f"HTTP {resp.status_code}: {resp.text[:120]}"
    except requests.exceptions.Timeout:
        return False, 408, f"Connection timed out reaching {url}"
    except requests.exceptions.ConnectionError:
        return False, 503, f"Failed to connect to host: {host_clean}"
    except Exception as exc:
        return False, 500, f"Error validating token: {str(exc)}"
