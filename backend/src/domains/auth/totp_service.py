"""TOTP-based Two-Factor Authentication service."""
import threading
import time
from datetime import datetime, timezone

import base64
import io
import pyotp
import qrcode
from pyotp.utils import compare_digest

from src.core.config import settings


def generate_totp_secret() -> str:
    return pyotp.random_base32()


def get_totp_uri(secret: str, email: str, issuer: str = "ApexBooks") -> str:
    totp = pyotp.TOTP(secret)
    return totp.provisioning_uri(name=email, issuer_name=issuer)


def generate_qr_base64(uri: str) -> str:
    img = qrcode.make(uri)
    buf = io.BytesIO()
    img.save(buf, format='PNG')
    return base64.b64encode(buf.getvalue()).decode()


def verify_totp(secret: str, token: str) -> bool:
    totp = pyotp.TOTP(secret)
    return totp.verify(token, valid_window=1)


# ---------------------------------------------------------------------------
# Single-use TOTP codes
# ---------------------------------------------------------------------------
# A TOTP code is valid for its 30-second window plus a tolerance window for
# clock skew, so a captured code could otherwise be replayed within that
# window. We keep a small in-memory spend registry keyed by (user, window):
# the first successful use of a code spends it for that window.
#
# The registry is bounded: entries are pruned once their window + skew slack
# has elapsed, so memory stays flat regardless of activity.

_TOTP_WINDOW_SECONDS = 30
_TOTP_SKEW_SLACK_SECONDS = 60  # keep spent markers for window + skew + margin

_USED_TOTP_CODES = {}  # key: str -> expiry epoch seconds
_USED_TOTP_CODES_LOCK = threading.Lock()


def _spent_key(secret: str, window: int) -> str:
    # The secret is part of the key: during rotation the old and new secrets
    # produce different codes in the same window, and spending a code of one
    # secret must not block a valid code of the other.
    return f"{secret}:{window}"


def _prune_spent(now: float) -> None:
    expired = [k for k, exp in _USED_TOTP_CODES.items() if exp <= now]
    for k in expired:
        _USED_TOTP_CODES.pop(k, None)


def verify_totp_spend(secret: str, token: str, user_id: str) -> bool:
    """Verify a TOTP code and mark it spent so it cannot be replayed.

    Accepts the current window plus one adjacent window either side
    (valid_window=1, matching ``verify_totp``). The first successful use of
    a code spends it: any later attempt with the same code fails.
    """
    totp = pyotp.TOTP(secret)
    now = time.time()
    current_window = totp.timecode(datetime.fromtimestamp(now, tz=timezone.utc))
    for offset in (-1, 0, 1):
        window = current_window + offset
        expected = totp.at(window * _TOTP_WINDOW_SECONDS)
        if not compare_digest(expected, token):
            continue
        key = _spent_key(secret, window)
        with _USED_TOTP_CODES_LOCK:
            _prune_spent(now)
            if key in _USED_TOTP_CODES:
                return False  # already used in this window
            _USED_TOTP_CODES[key] = now + _TOTP_WINDOW_SECONDS + _TOTP_SKEW_SLACK_SECONDS
        return True
    return False
