import requests
from typing import Optional, Dict, Any
from src.core.config import settings


class GSTVerificationError(Exception):
    pass


class GSTVerificationService:
    """Verifies GSTIN via gstverify.dubey.app API (self-hosted or hosted)."""

    @staticmethod
    def get_captcha() -> Dict[str, Any]:
        """Fetch captcha image (base64) + session ID from the GST portal."""
        try:
            resp = requests.get(
                f"{settings.GST_VERIFY_BASE_URL}/api/v1/getCaptcha",
                timeout=15,
            )
            resp.raise_for_status()
            data = resp.json()
            return {
                "session_id": data.get("sessionId", ""),
                "image": data.get("image", ""),
            }
        except requests.exceptions.RequestException as e:
            raise GSTVerificationError(f"Failed to fetch captcha: {e}")

    @staticmethod
    def verify_gstin(gstin: str, captcha: str, session_id: str) -> Dict[str, Any]:
        """Verify a GSTIN using captcha + session ID. Returns taxpayer details."""
        try:
            resp = requests.post(
                f"{settings.GST_VERIFY_BASE_URL}/api/v1/getGSTDetails",
                json={
                    "sessionId": session_id,
                    "GSTIN": gstin,
                    "captcha": captcha,
                },
                timeout=20,
            )
            resp.raise_for_status()
            data = resp.json()

            # Normalise response
            return {
                "gstin": data.get("gstin", gstin),
                "legal_name": data.get("lgnm", ""),
                "trade_name": data.get("tradeNam", ""),
                "status": data.get("sts", ""),
                "registration_date": data.get("rgdt", ""),
                "business_type": data.get("ctb", ""),
                "taxpayer_type": data.get("dty", ""),
                "address": data.get("pradr", {}).get("adr", ""),
                "state_code": gstin[:2] if len(gstin) >= 2 else "",
                "nature_of_business": data.get("nba", []),
                "is_field_visit": data.get("isFieldVisitConducted", ""),
                "e_invoice_status": data.get("einvoiceStatus", ""),
            }
        except requests.exceptions.RequestException as e:
            raise GSTVerificationError(f"GSTIN verification failed: {e}")
