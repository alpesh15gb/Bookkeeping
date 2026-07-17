from __future__ import annotations

import base64
import hashlib
import json
import uuid
from datetime import datetime, timezone
from typing import Any

from cryptography.fernet import Fernet

from src.core.config import settings


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def sha256_hex(value: bytes | str) -> str:
    payload = value.encode("utf-8") if isinstance(value, str) else value
    return hashlib.sha256(payload).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def generate_request_id() -> str:
    return f"req_{uuid.uuid4().hex.upper()[:26]}"


def api_key_prefix(api_key: str) -> str:
    return api_key[:12]


def _cipher() -> Fernet:
    digest = hashlib.sha256(settings.SECRET_KEY.encode("utf-8")).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def encrypt_text(value: str) -> str:
    return _cipher().encrypt(value.encode("utf-8")).decode("ascii")


def decrypt_text(value: str) -> str:
    return _cipher().decrypt(value.encode("ascii")).decode("utf-8")
