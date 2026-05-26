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
from pydantic import field_validator, model_validator


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
    ALLOWED_ORIGINS: str = "http://localhost:5173,http://localhost:3000,https://apexbooks.in,https://api.apexbooks.in,tauri://localhost,tauri://com.apexbooks.desktop"

    # ----------------------------------------------------------------
    # Email (SMTP / SendGrid)
    # ----------------------------------------------------------------
    SMTP_HOST: str = "smtp.hostinger.com"
    SMTP_PORT: int = 587
    SMTP_USER: str = "support@apexbooks.in"
    SMTP_PASSWORD: str = "Adish@786#"
    EMAIL_FROM: str = "support@apexbooks.in"

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
        if not v or len(v) < 32:
            raise ValueError(
                f"{info.field_name} must be set to a strong random value. "
                f"Generate one with: python -c \"import secrets; print(secrets.token_hex(64))\""
            )
        return v

    @property
    def allowed_origins_list(self) -> List[str]:
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]

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
settings = get_settings()
