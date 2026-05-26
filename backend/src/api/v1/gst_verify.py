from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional
from src.api.deps import enforce_permission
from src.core.database import get_db_session
from sqlalchemy.orm import Session
from src.domains.taxation.gst_verify.service import GSTVerificationService, GSTVerificationError

router = APIRouter(prefix="/gst/verify", tags=["GST Verification"])


class CaptchaResponse(BaseModel):
    session_id: str
    image: str  # base64-encoded PNG


class VerifyRequest(BaseModel):
    gstin: str
    captcha: str
    session_id: str


class VerifyResponse(BaseModel):
    gstin: str
    legal_name: Optional[str] = None
    trade_name: Optional[str] = None
    status: Optional[str] = None
    registration_date: Optional[str] = None
    business_type: Optional[str] = None
    taxpayer_type: Optional[str] = None
    address: Optional[str] = None
    state_code: Optional[str] = None
    nature_of_business: list = []
    is_field_visit: Optional[str] = None
    e_invoice_status: Optional[str] = None


@router.get("/captcha", response_model=CaptchaResponse)
def get_captcha(
    db: Session = Depends(get_db_session),
    tenant_id = Depends(enforce_permission("contact:create")),
):
    """Fetch captcha image + session ID for GSTIN verification."""
    try:
        result = GSTVerificationService.get_captcha()
        return CaptchaResponse(
            session_id=result["session_id"],
            image=result["image"],
        )
    except GSTVerificationError as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.post("", response_model=VerifyResponse)
def verify_gstin(
    payload: VerifyRequest,
    db: Session = Depends(get_db_session),
    tenant_id = Depends(enforce_permission("contact:create")),
):
    """Verify a GSTIN using captcha. Returns taxpayer details."""
    if len(payload.gstin) != 15:
        raise HTTPException(status_code=400, detail="GSTIN must be 15 characters.")

    try:
        result = GSTVerificationService.verify_gstin(
            gstin=payload.gstin,
            captcha=payload.captcha,
            session_id=payload.session_id,
        )
        return VerifyResponse(**result)
    except GSTVerificationError as e:
        raise HTTPException(status_code=502, detail=str(e))
