"""
src/core/rate_limiter.py
Slowapi-based rate limiter with Redis-backed storage (falls back to in-memory for tests).
Rate limiting can be disabled via RATE_LIMIT_ENABLED setting (useful during tests).
"""
import logging

from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request, status
from fastapi.responses import JSONResponse
from slowapi.middleware import SlowAPIMiddleware

from src.core.config import settings

logger = logging.getLogger(__name__)

if settings.RATE_LIMIT_ENABLED:
    # Try Redis-backed storage, fall back to in-memory
    try:
        from redis import Redis
        r = Redis.from_url(settings.REDIS_URL, socket_connect_timeout=1)
        r.ping()
        r.close()
        storage_uri = settings.REDIS_URL
    except Exception:
        storage_uri = "memory://"

    limiter = Limiter(
        key_func=get_remote_address,
        storage_uri=storage_uri,
        strategy="moving-window",
    )
else:
    # No-op limiter when rate limiting is disabled
    limiter = Limiter(
        key_func=lambda: "test",
        storage_uri="memory://",
        strategy="fixed-window",
        enabled=False,
    )


def rate_limiter_exceeded_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content={"detail": "Rate limit exceeded. Please try again later.", "code": "RATE_LIMIT_EXCEEDED"},
    )
