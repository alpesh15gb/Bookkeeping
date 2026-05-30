"""Sentry integration for error tracking."""
import logging
from src.core.config import settings

logger = logging.getLogger("bookkeeping.sentry")

def init_sentry():
    if not settings.SENTRY_DSN:
        return
    try:
        import sentry_sdk
        from sentry_sdk.integrations.fastapi import FastApiIntegration
        from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

        sentry_sdk.init(
            dsn=settings.SENTRY_DSN,
            environment=settings.APP_ENV,
            integrations=[
                FastApiIntegration(),
                SqlalchemyIntegration(),
            ],
            traces_sample_rate=0.1 if settings.is_production else 0,
            profiles_sample_rate=0.1 if settings.is_production else 0,
        )
        logger.info("Sentry initialized.")
    except ImportError:
        logger.warning("sentry-sdk not installed. Run: pip install sentry-sdk")
    except Exception as e:
        logger.error(f"Sentry init failed: {e}")
