from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from src.api.deps import enforce_permission
from src.domains.taxation.hsn_directory import lookup_hsn

router = APIRouter(prefix="/gst/hsn", tags=["HSN/SAC Lookup"])


class HSNLookupResponse(BaseModel):
    hsn_code: str
    description: str


@router.get("/{hsn_code}", response_model=HSNLookupResponse)
def lookup_hsn_code(
    hsn_code: str,
    tenant_id = Depends(enforce_permission("invoice:create")),
):
    """Look up the description for a given 6-8 digit HSN/SAC code."""
    if not hsn_code.isdigit() or not (6 <= len(hsn_code) <= 8):
        raise HTTPException(status_code=400, detail="HSN/SAC code must be 6-8 digits.")
    description = lookup_hsn(hsn_code)
    if not description:
        raise HTTPException(status_code=404, detail=f"HSN/SAC code {hsn_code} not found in directory.")
    return HSNLookupResponse(hsn_code=hsn_code, description=description)
