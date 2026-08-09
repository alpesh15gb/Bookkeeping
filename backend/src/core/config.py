"""
src/core/config.py
Central application configuration via pydantic-settings.
All secrets and environment variables are defined here.
The application will fail to start if required variables are missing.
"""
import os
from functools import lru_cache
from typing import List
from pydantic_settings import BaseSettings
from pydantic import field_validator


class Settings(BaseSettings):
    # ----------------------------------------------------------------
    # Application
    # ----------------------------------------------------------------
    APP_ENV: str = "development"          # development | staging | production
    DEBUG: bool = False
    SEED_ON_STARTUP: bool = False         # Only true in dev/demo
    APP_URL: str = "http://localhost:5173" # Frontend URL for reset links

    # ----------------------------------------------------------------
    # Database
    # ----------------------------------------------------------------
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./bookkeeping.db")

    # ----------------------------------------------------------------
    # Redis
    # ----------------------------------------------------------------
    REDIS_URL: str = "redis://localhost:6379/0"

    # ----------------------------------------------------------------
    # JWT Authentication
    # ----------------------------------------------------------------
    JWT_SECRET_KEY: str = ""
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # ----------------------------------------------------------------
    # Encryption
    # ----------------------------------------------------------------
    SECRET_KEY: str = ""

    # ----------------------------------------------------------------
    # CORS
    # ----------------------------------------------------------------
    ALLOWED_ORIGINS: str = "http://localhost:5173,http://localhost:3000,https://apexbooks.in,https://api.apexbooks.in,https://app.apexbooks.in,tauri://localhost,tauri://com.apexbooks.desktop"

    # ----------------------------------------------------------------
    # Email (SMTP / SendGrid)
    # ----------------------------------------------------------------
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    EMAIL_FROM: str = ""

    # ----------------------------------------------------------------
    # File Storage (S3-compatible)
    # ----------------------------------------------------------------
    S3_BUCKET: str = "bookkeeping-documents"
    S3_REGION: str = "ap-south-1"
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""

    # ----------------------------------------------------------------
    # IRP (Invoice Registration Portal) — NIC e-Invoice
    # ----------------------------------------------------------------
    IRP_BASE_URL: str = "https://einvoice1-sandbox.nic.in"
    IRP_CLIENT_ID: str = ""
    IRP_CLIENT_SECRET: str = ""
    IRP_USERNAME: str = ""
    IRP_PASSWORD: str = ""
    # Explicit opt-in for automated tests/local demos. Never enable in production.
    COMPLIANCE_MOCK_ENABLED: bool = False

    # ----------------------------------------------------------------
    # GST Verification (gstverify.dubey.app)
    # ----------------------------------------------------------------
    GST_VERIFY_API_KEY: str = ""
    GST_VERIFY_BASE_URL: str = "https://api.gstverify.dubey.app"

    # ----------------------------------------------------------------
    # Sentry
    # ----------------------------------------------------------------
    SENTRY_DSN: str = ""

    # ----------------------------------------------------------------
    # Cartunez / Medusa outbound integration
    # ----------------------------------------------------------------
    CARTUNEZ_MEDUSA_BASE_URL: str = ""
    CARTUNEZ_MEDUSA_API_KEY: str = ""
    CARTUNEZ_OUTBOUND_ENABLED: bool = False
    CARTUNEZ_DELIVERY_TIMEOUT_SECONDS: int = 15
    CARTUNEZ_DELIVERY_BATCH_SIZE: int = 25

    # ----------------------------------------------------------------
    # OCR (Bill Scanning)
    # ----------------------------------------------------------------
    OCR_ENGINE: str = "paddleocr"  # "google_vision" or "paddleocr"
    GOOGLE_VISION_API_KEY: str = ""
    NVIDIA_NIM_API_KEY: str = ""
    NVIDIA_NIM_MODEL: str = "meta/llama-3.2-11b-vision-instruct"

    # ----------------------------------------------------------------
    # Idempotency
    # ----------------------------------------------------------------
    # A PROCESSING claim older than this is presumed abandoned (the process
    # died before its business transaction committed).  Any request whose
    # financial transaction committed has already flipped the claim to
    # COMMITTED atomically, so this timeout never re-runs committed work — it
    # only re-runs requests that provably never committed.
    IDEMPOTENCY_STALE_SECONDS: int = 120
    # Financial mutations (invoice / bill / payment / journal creation) must
    # carry an Idempotency-Key so a client retry can never double-post money
    # movements.  Disable only for legacy clients that predate the rule.
    REQUIRE_IDEMPOTENCY_KEY: bool = True

    # ----------------------------------------------------------------
    # Rate Limiting
    # ----------------------------------------------------------------
    RATE_LIMIT_ENABLED: bool = True                # Disable for tests
    RATE_LIMIT_LOGIN: str = "10/minute"
    RATE_LIMIT_REGISTER: str = "5/minute"
    RATE_LIMIT_REPORTS: str = "60/minute"
    RATE_LIMIT_DEFAULT: str = "200/minute"

    @field_validator("JWT_SECRET_KEY", "SECRET_KEY")
    @classmethod
    def secret_must_be_set(cls, v: str, info) -> str:
        import os
        # Only enforce strong secret in non-development environments
        env = os.getenv("APP_ENV", "development")
        if env != "development":
            if not v or len(v) < 32:
                raise ValueError(
                    f"{info.field_name} must be set to a strong random value. "
                    f"Generate one with: python -c \"import secrets; print(secrets.token_hex(64))\""
                )
        return v

    @field_validator("RATE_LIMIT_ENABLED")
    @classmethod
    def rate_limit_must_be_enabled_in_production(cls, v: bool, info) -> bool:
        import os
        if os.getenv("APP_ENV", "development") == "production" and not v:
            raise ValueError("Rate limiting cannot be disabled in production.")
        return v

    @field_validator("CARTUNEZ_MEDUSA_BASE_URL")
    @classmethod
    def medusa_base_url_must_be_https(cls, v: str) -> str:
        value = v.strip().rstrip("/")
        if value and not value.startswith("https://"):
            raise ValueError("CARTUNEZ_MEDUSA_BASE_URL must use HTTPS.")
        return value

    @field_validator("CARTUNEZ_DELIVERY_TIMEOUT_SECONDS")
    @classmethod
    def delivery_timeout_must_be_bounded(cls, v: int) -> int:
        if not 1 <= v <= 120:
            raise ValueError("CARTUNEZ_DELIVERY_TIMEOUT_SECONDS must be between 1 and 120.")
        return v

    @field_validator("CARTUNEZ_DELIVERY_BATCH_SIZE")
    @classmethod
    def delivery_batch_must_be_bounded(cls, v: int) -> int:
        if not 1 <= v <= 500:
            raise ValueError("CARTUNEZ_DELIVERY_BATCH_SIZE must be between 1 and 500.")
        return v

    @property
    def allowed_origins_list(self) -> List[str]:
        return sorted({origin.strip() for origin in self.ALLOWED_ORIGINS.split(",") if origin.strip()})

    @property
    def is_production(self) -> bool:
        return self.APP_ENV == "production"

    @property
    def is_development(self) -> bool:
        return self.APP_ENV == "development"

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": True,
        "extra": "ignore",
    }


@lru_cache()
def get_settings() -> Settings:
    """
    Returns the cached application settings singleton.
    Call this everywhere instead of importing Settings directly.
    """
    return Settings()


# Convenience alias — use `settings.JWT_SECRET_KEY` anywhere
# Lazy-initialized to avoid validation side-effects at import time
_settings_instance = None


def __getattr__(name: str):
    global _settings_instance
    if name == "settings":
        if _settings_instance is None:
            _settings_instance = get_settings()
        return _settings_instance
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
