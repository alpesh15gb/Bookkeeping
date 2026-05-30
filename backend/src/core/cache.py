"""Simple Redis-based query result cache."""
import json
import hashlib
from typing import Optional, Any
from src.core.config import settings

_cache_client = None

def _get_client():
    global _cache_client
    if _cache_client is None:
        try:
            import redis
            _cache_client = redis.from_url(settings.REDIS_URL, socket_connect_timeout=2)
        except Exception:
            _cache_client = None
    return _cache_client

def cache_get(key: str) -> Optional[Any]:
    client = _get_client()
    if client is None:
        return None
    try:
        data = client.get(f"cache:{key}")
        if data:
            return json.loads(data)
    except Exception:
        pass
    return None

def cache_set(key: str, value: Any, ttl_seconds: int = 300) -> None:
    client = _get_client()
    if client is None:
        return
    try:
        client.setex(f"cache:{key}", ttl_seconds, json.dumps(value, default=str))
    except Exception:
        pass

def cache_invalidate(pattern: str = "cache:*") -> None:
    client = _get_client()
    if client is None:
        return
    try:
        keys = client.keys(pattern)
        if keys:
            client.delete(*keys)
    except Exception:
        pass

def make_cache_key(*args) -> str:
    raw = json.dumps([str(a) for a in args], sort_keys=True)
    return hashlib.md5(raw.encode()).hexdigest()
