"""Application settings, read from environment variables prefixed CAMPUSHUB_ (or a .env file)."""
from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CAMPUSHUB_", env_file=".env", extra="ignore")

    # --- Database (RDS PostgreSQL; in AWS, point this at the RDS Proxy endpoint) ---
    database_url: str = "postgresql://campushub:campushub@localhost:5432/campushub"
    db_pool_min_size: int = 0
    db_pool_max_size: int = 5
    # 0 turns off asyncpg's prepared-statement cache, which RDS Proxy / PgBouncer need.
    db_statement_cache_size: int = 0

    # --- Auth ---
    # "cognito": verify the Cognito ID token sent as "Authorization: Bearer <token>".
    # "dev":     trust an "X-Dev-User: someone@iisc.ac.in" header. Local development only;
    #            the app refuses to start in Lambda with this mode.
    auth_mode: Literal["cognito", "dev"] = "cognito"
    cognito_region: str = "ap-south-1"
    cognito_user_pool_id: str = ""
    cognito_app_client_id: str = ""

    # --- S3 uploads ---
    s3_bucket: str = "campushub-uploads"
    s3_region: str = "ap-south-1"
    s3_endpoint_url: str | None = None   # e.g. http://localhost:9000 for MinIO in docker-compose
    cdn_base_url: str | None = None      # CloudFront URL, e.g. https://d1234.cloudfront.net
    upload_url_expiry_seconds: int = 900
    download_url_expiry_seconds: int = 3600

    # --- HTTP ---
    api_prefix: str = "/api/v1"
    cors_allow_origins: list[str] = Field(default_factory=lambda: ["*"])


@lru_cache
def get_settings() -> Settings:
    return Settings()
