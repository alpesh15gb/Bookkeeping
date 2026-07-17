from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from src.core.database import get_db_session
from src.integrations.cartunez.customer_service import CartunezCustomerService


router = APIRouter(prefix="/api/integrations/medusa/v1", tags=["ApexBooks Receiver"])
service = CartunezCustomerService()


@router.post("/customers")
async def create_customer(request: Request, db: Session = Depends(get_db_session)):
    result = await service.process_create(request, db)
    return JSONResponse(status_code=result.status_code, content=result.body, headers=result.headers)
