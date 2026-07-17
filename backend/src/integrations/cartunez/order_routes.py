from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from src.core.database import get_db_session
from src.integrations.cartunez.order_service import CartunezOrderService


router = APIRouter(prefix="/api/integrations/medusa/v1", tags=["ApexBooks Receiver"])
service = CartunezOrderService()


def _response(result):
    return JSONResponse(status_code=result.status_code, content=result.body, headers=result.headers)


@router.post("/orders")
async def create_order(request: Request, db: Session = Depends(get_db_session)):
    return _response(await service.process_create(request, db))


@router.patch("/orders/{external_order_id}")
async def update_order(external_order_id: str, request: Request, db: Session = Depends(get_db_session)):
    return _response(await service.process_update(request, db, external_order_id))


@router.post("/orders/{external_order_id}/cancel")
async def cancel_order(external_order_id: str, request: Request, db: Session = Depends(get_db_session)):
    return _response(await service.process_cancel(request, db, external_order_id))
