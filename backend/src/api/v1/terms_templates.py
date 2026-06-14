from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from datetime import datetime, timezone

from src.core.database import get_db_session
from src.infrastructure.database.models import TermsTemplate
from src.schemas.document import TermsTemplateCreate, TermsTemplateUpdate, TermsTemplateResponse
from src.api.deps import enforce_permission
from src.core.rate_limiter import limiter
from src.core.config import settings

router = APIRouter(prefix="/terms-templates", tags=["Terms Templates"])

# India-specific preset templates
INDIA_PRESETS = [
    {
        "name": "Standard Services",
        "content": "<p>1. Payment is due within 30 days of invoice date.</p><p>2. A late fee of 1.5% per month will be charged on overdue amounts.</p><p>3. All disputes subject to local jurisdiction.</p><p>4. Goods/services once delivered will not be taken back.</p><p>5. TDS/TCS as applicable under Income Tax Act, 1961.</p>"
    },
    {
        "name": "Standard Goods",
        "content": "<p>1. Payment is due within 15 days of invoice date.</p><p>2. Risk transfers to buyer upon delivery.</p><p>3. Returns accepted only for manufacturing defects within 7 days.</p><p>4. Warranty as per manufacturer terms.</p><p>5. Interest at 18% p.a. on overdue payments.</p>"
    },
    {
        "name": "Export / International",
        "content": "<p>1. Payment by Irrevocable L/C or T/T advance.</p><p>2. Incoterms: FOB (port of loading).</p><p>3. Goods once shipped cannot be returned.</p><p>4. Claims must be filed within 30 days of delivery.</p><p>5. Subject to UCP 600 for L/C transactions.</p>"
    },
    {
        "name": "Manufacturing / Job Work",
        "content": "<p>1. Material to be supplied by buyer within 7 days of order.</p><p>2. Job work charges payable on completion.</p><p>3. Buyer responsible for quality inspection before dispatch.</p><p>4. Retention money: 5% payable after 90 days of satisfactory commissioning.</p><p>5. Force majeure clause applies.</p>"
    },
    {
        "name": "Freelancer / Consultant",
        "content": "<p>1. 50% advance payment required before project commencement.</p><p>2. Remaining 50% due within 7 days of project completion.</p><p>3. Revisions beyond 2 rounds will be billed separately.</p><p>4. Intellectual property transfers upon full payment.</p><p>5. Project timeline may vary based on feedback turnaround.</p>"
    },
    {
        "name": "Composition Dealer",
        "content": "<p>1. No GST charged (Composition Scheme under Section 10).</p><p>2. Supply limited to intra-state only.</p><p>3. No Input Tax Credit available to buyer.</p><p>4. Payment due within 30 days.</p><p>5. Subject to provisions of CGST Act, 2017.</p>"
    },
    {
        "name": "SEZ / Export (LUT)",
        "content": "<p>1. Supply under Letter of Undertaking (LUT) without payment of IGST.</p><p>2. FOB/CIF value as declared in shipping bill.</p><p>3. Buyer must provide shipping bill details within 15 days.</p><p>4. Refund of taxes as per DGFT guidelines.</p><p>5. Subject to FTP 2023 provisions.</p>"
    },
    {
        "name": "E-Commerce / Online",
        "content": "<p>1. Orders confirmed upon payment receipt.</p><p>2. Digital products: delivery via email/download link within 24 hours.</p><p>3. Physical products: shipped within 3-5 business days.</p><p>4. Refund policy: 7 days from delivery for physical goods.</p><p>5. No refund for digital products once downloaded.</p>"
    },
    {
        "name": "Construction / Real Estate",
        "content": "<p>1. Payment as per milestone schedule agreed separately.</p><p>2. 1% TDS deductible under Section 194-IA.</p><p>3. GST as applicable (12% for under-construction, 1% for affordable housing).</p><p>4. Possession timeline as per RERA registration.</p><p>5. Force majeure provisions apply.</p>"
    },
    {
        "name": "Transport / Logistics",
        "content": "<p>1. Carrier liability limited to actual loss or Rs. 10,000 per consignment, whichever is lower.</p><p>2. Claims must be filed within 7 days of delivery.</p><p>3. Insurance arranged separately by consignor.</p><p>4. Demurrage charges apply for delayed unloading.</p><p>5. Subject to Motor Vehicles Act, 1988 provisions.</p>"
    },
    {
        "name": "IT / Software",
        "content": "<p>1. Annual Maintenance Charges (AMC) billed quarterly in advance.</p><p>2. Support hours: Mon-Sat, 9 AM - 6 PM IST.</p><p>3. Critical issues resolved within 4 hours SLA.</p><p>4. Data backup and security as per client requirements.</p><p>5. Source code ownership as per separate agreement.</p>"
    },
    {
        "name": "Professional Services (CA/Legal)",
        "content": "<p>1. Professional fees are non-refundable once advisory is rendered.</p><p>2. Retainer fees payable monthly in advance.</p><p>3. Out-of-pocket expenses billed separately with receipts.</p><p>4. Confidentiality maintained as per professional ethics.</p><p>5. Disputes subject to ICAI/Bar Council jurisdiction.</p>"
    },
    {
        "name": "Healthcare / Pharma",
        "content": "<p>1. All products subject to drug license regulations.</p><p>2. Expiry claims must be filed before product expiry date.</p><p>3. Temperature-sensitive items shipped with cold chain documentation.</p><p>4. Returns accepted only for damaged/expired goods.</p><p>5. Subject to CDSCO and state drug controller regulations.</p>"
    },
]


@router.post("", response_model=TermsTemplateResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_terms_template(
    request: Request,
    payload: TermsTemplateCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("settings:update")),
):
    template = TermsTemplate(
        tenant_id=tenant_id,
        name=payload.name,
        content=payload.content,
        is_preset=False,
        is_active=True,
    )
    db.add(template)
    db.commit()
    db.refresh(template)
    return template


@router.get("", response_model=List[TermsTemplateResponse])
def list_terms_templates(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("settings:view")),
):
    templates = db.query(TermsTemplate).filter(
        TermsTemplate.tenant_id.in_([tenant_id, None]),
        TermsTemplate.is_active == True,
    ).order_by(TermsTemplate.is_preset.desc(), TermsTemplate.name.asc()).all()
    return templates


@router.get("/presets", response_model=List[dict])
def get_preset_templates():
    """Returns India-specific preset terms templates (no auth required)."""
    return [{"name": p["name"], "content": p["content"]} for p in INDIA_PRESETS]


@router.get("/{id}", response_model=TermsTemplateResponse)
def get_terms_template(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("settings:view")),
):
    template = db.query(TermsTemplate).filter(
        TermsTemplate.id == id,
        TermsTemplate.tenant_id.in_([tenant_id, None]),
    ).first()
    if not template:
        raise HTTPException(status_code=404, detail="Template not found.")
    return template


@router.put("/{id}", response_model=TermsTemplateResponse)
def update_terms_template(
    id: uuid.UUID,
    payload: TermsTemplateUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("settings:update")),
):
    template = db.query(TermsTemplate).filter(
        TermsTemplate.id == id,
        TermsTemplate.tenant_id == tenant_id,
    ).first()
    if not template:
        raise HTTPException(status_code=404, detail="Template not found.")
    if template.is_preset:
        raise HTTPException(status_code=400, detail="Cannot edit preset templates.")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(template, field, value)

    db.commit()
    db.refresh(template)
    return template


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_terms_template(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("settings:update")),
):
    template = db.query(TermsTemplate).filter(
        TermsTemplate.id == id,
        TermsTemplate.tenant_id == tenant_id,
    ).first()
    if not template:
        raise HTTPException(status_code=404, detail="Template not found.")
    if template.is_preset:
        raise HTTPException(status_code=400, detail="Cannot delete preset templates.")

    db.delete(template)
    db.commit()
