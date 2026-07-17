from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from src.core.database import get_db_session
from src.integrations.cartunez.payment_service import CartunezPaymentService


router = APIRouter(prefix="/api/integrations/medusa/v1", tags=["ApexBooks Receiver"])
service = CartunezPaymentService()


@router.post("/payments/captured")
async def capture_payment(request: Request, db: Session = Depends(get_db_session)):
    result = await service.process_capture(request, db)
    return JSONResponse(status_code=result.status_code, content=result.body, headers=result.headers)
