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

    # --- Category auto-suggestion (app/categories_suggest.py, future plan §2.4) ---
    # bge-small-en-v1.5 score of the title against each category (its phrase and recent listings).
    # Suggest only at or above the threshold AND with this lead over the runner-up. Calibrated with
    # scripts/calibrate_category_suggest.py: 55/79 right, 2 wrong, silent on titles that fit nothing.
    category_suggest_threshold: float = 0.52
    category_suggest_margin: float = 0.03

    # --- Seller trust score (app/seller_trust.py, future plan §1.5) ---
    # A strike is one listing a moderator removed while resolving a report against its seller —
    # never a raw report count. Two severity tiers, no decay by default (§1.5.2): a single severe
    # strike (illegal items) blocks immediately; non-severe strikes build up a short ladder.
    # Thresholds are a starting proposal from the plan doc, not a final policy decision.
    seller_strike_severe_threshold: int = 1     # severe strikes -> "Blocked Seller" + posting suspended
    seller_strike_negative_threshold: int = 2   # non-severe strikes -> "Negative Seller" tag shown
    seller_strike_blocked_threshold: int = 3    # non-severe strikes -> "Blocked Seller" + posting suspended

    # --- Automatic flagging (app/screening.py, future plan §1.6) ---
    auto_flag: bool = True

    # --- Meal alerts (app/mess_alerts.py) ---
    # In AWS an EventBridge schedule runs app.jobs.meal_alerts_handler every 5 minutes. Locally (or on
    # EC2) set this to check from inside the API instead, e.g. 60. 0 = off; never used inside Lambda.
    meal_alert_poll_seconds: int = 0
    # Also check whenever an app fetches its notifications (every minute while it's open), so alerts
    # go out without any scheduler while people are using CampusHub.
    meal_alerts_on_requests: bool = True

    # --- Course feedback sentiment (app/sentiment_backends.py) ---
    # auto: the local model if its files are there, else the word list. comprehend: Amazon Comprehend.
    sentiment_backend: Literal["auto", "local", "comprehend", "lexicon"] = "auto"
    comprehend_region: str = "ap-south-1"

    # --- HTTP ---
    api_prefix: str = "/api/v1"
    cors_allow_origins: list[str] = Field(default_factory=lambda: ["*"])
    # Swagger and ReDoc. Default: on locally and on EC2, off inside Lambda.
    docs_enabled: bool | None = None

    # --- Redis cache (ElastiCache; unset means "no cache", every call below is a no-op) ---
    # A short-TTL cache-aside layer (app/cache.py) for the read-heavy list/browse endpoints that
    # queued up on the DB connection pool under load testing. redis_host unset => caching is off.
    redis_host: str | None = None
    redis_port: int = 6379
    redis_auth_token: str | None = None
    # Lambda: the AUTH token's Secrets Manager ARN instead of the token itself (read once per
    # container by app/cache.py, same as database_secret_arn). Ignored if redis_auth_token is set.
    redis_auth_secret_arn: str | None = None
    redis_tls: bool = False
    redis_default_ttl_seconds: int = 20
    redis_connect_timeout_seconds: float = 1.0

    @model_validator(mode="after")
    def _environment_defaults(self):
        if self.db_pool_max_size is None:
            # In Lambda, RDS Proxy does the real pooling, so each container only needs a couple of
            # connections of its own. On EC2 there's one long-lived process: size its pool for real
            # concurrency (a db.t4g.micro's default max_connections is well above this) rather than
            # the old default of 5, which queued requests behind the pool itself under load testing.
            self.db_pool_max_size = 2 if in_lambda() else 20
        if self.docs_enabled is None:
            self.docs_enabled = not in_lambda()
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
