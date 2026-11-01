"""Application settings, read from environment variables prefixed CAMPUSHUB_ (or a .env file)."""
import os
from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def in_lambda() -> bool:
    return bool(os.environ.get("AWS_LAMBDA_FUNCTION_NAME"))


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CAMPUSHUB_", env_file=".env", extra="ignore")

    # --- Database (RDS PostgreSQL; in AWS, point this at the RDS Proxy endpoint) ---
    database_url: str = "postgresql://campushub:campushub@localhost:5432/campushub"
    # In AWS, keep the password out of the environment: set this to the Secrets Manager secret
    # holding the database credentials (RDS format: {"username": ..., "password": ...}). Its user
    # and password then replace the ones in database_url; host, port and database stay from the URL.
    database_secret_arn: str | None = None
    db_pool_min_size: int = 0
    # Default: 2 inside Lambda (RDS Proxy does the real pooling), 5 elsewhere.
    db_pool_max_size: int | None = None
    # 0 turns off asyncpg's prepared-statement cache, which RDS Proxy / PgBouncer need.
    db_statement_cache_size: int = 0
    # A container frozen longer than this may hold connections the proxy has closed; replace them.
    db_idle_reconnect_seconds: int = 300

    # --- Auth ---
    # "cognito": verify the Cognito ID token sent as "Authorization: Bearer <token>".
    # "dev":     trust an "X-Dev-User: someone@iisc.ac.in" header, from this machine only.
    #            Local development only: it also needs allow_dev_auth=true, and the app
    #            refuses to start with it inside Lambda.
    auth_mode: Literal["cognito", "dev"] = "cognito"
    allow_dev_auth: bool = False
    # Sharing a dev server on a private network (e.g. teammates on the same Wi-Fi): other
    # machines may use X-Dev-User only if they also send "X-Dev-Key: <this value>".
    dev_auth_key: str | None = None
    cognito_region: str = "ap-south-1"
    cognito_user_pool_id: str = ""
    cognito_app_client_id: str = ""
    jwks_timeout_seconds: float = 5.0

    # --- Dev sign-in OTP email ---
    # Only used in auth_mode="dev": the "send OTP" step on the sign-in dialog emails a real
    # 6-digit code instead of accepting any value. Without SMTP configured, the code is logged
    # to the server console instead, so local development still works with no mail account.
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "CampusHub <no-reply@campushub.local>"
    otp_ttl_seconds: int = 600
    otp_resend_cooldown_seconds: int = 30
    otp_max_attempts: int = 5

    # --- S3 uploads ---
    s3_bucket: str = "campushub-uploads"
    s3_region: str = "ap-south-1"
    s3_endpoint_url: str | None = None   # e.g. http://localhost:9000 for MinIO in docker-compose
    upload_url_expiry_seconds: int = 900
    download_url_expiry_seconds: int = 3600
    # CloudFront in front of the private bucket. File links are signed with this CloudFront key
    # pair and expire like presigned S3 links do, so a removed file can't stay reachable.
    cdn_base_url: str | None = None      # e.g. https://d1234.cloudfront.net
    cdn_key_pair_id: str | None = None   # public key ID registered in the CloudFront key group
    cdn_private_key: str | None = None   # matching PEM private key (inject from Secrets Manager)

    # --- Notifications ---
    # On Lambda, background tasks finish before the response is returned, so cap their time.
    push_timeout_seconds: float = 3.0

    # --- Lost & Found matching (app/matching) ---
    # "lambda": the API asynchronously invokes match_function (the matcher Lambda, Dockerfile.matcher).
    # "inline": the API runs the models itself in a background task (local dev; needs
    #           requirements-matching.txt and scripts/fetch_match_models.py).
    # "off":    the old rule only: same category, compatible times.
    # "auto":   lambda if match_function is set, else inline if the models are installed, else off.
    match_mode: Literal["auto", "lambda", "inline", "off"] = "auto"
    match_function: str | None = None
    match_model_dir: str | None = None   # default: backend/models
    match_possible: float = 0.4           # listed under "Possible matches"
    match_strong: float = 0.75            # "Strong match": the lost report's owner is alerted

    # --- HTTP ---
    api_prefix: str = "/api/v1"
    cors_allow_origins: list[str] = Field(default_factory=lambda: ["*"])
    # Swagger and ReDoc. Default: on locally and on EC2, off inside Lambda.
    docs_enabled: bool | None = None

    @model_validator(mode="after")
    def _environment_defaults(self):
        if self.db_pool_max_size is None:
            self.db_pool_max_size = 2 if in_lambda() else 5
        if self.docs_enabled is None:
            self.docs_enabled = not in_lambda()
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
