from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from src.core.database import get_db_session
from src.integrations.cartunez.master_service import CartunezMasterDataService


router = APIRouter(
    prefix="/api/integrations/apexbooks/v1",
    tags=["ApexBooks Receiver"],
)

service = CartunezMasterDataService()


def _response(result):
    return JSONResponse(status_code=result.status_code, content=result.body, headers=result.headers)


@router.put("/products/{apexbooks_product_id}")
async def upsert_product(apexbooks_product_id: str, request: Request, db: Session = Depends(get_db_session)):
    return _response(await service.process_product(request, db, apexbooks_product_id))


@router.put("/prices/{apexbooks_product_id}")
async def replace_prices(apexbooks_product_id: str, request: Request, db: Session = Depends(get_db_session)):
    return _response(await service.process_prices(request, db, apexbooks_product_id))


@router.put("/inventory/{apexbooks_product_id}")
async def replace_inventory(apexbooks_product_id: str, request: Request, db: Session = Depends(get_db_session)):
    return _response(await service.process_inventory(request, db, apexbooks_product_id))


@router.put("/customers/{apexbooks_customer_id}")
async def upsert_customer(apexbooks_customer_id: str, request: Request, db: Session = Depends(get_db_session)):
    return _response(await service.process_customer(request, db, apexbooks_customer_id))
