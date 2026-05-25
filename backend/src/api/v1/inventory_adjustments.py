from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal
from sqlalchemy import func

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    InventoryAdjustment, InventoryAdjustmentLine, Product, JournalEntry, JournalLine, StockLedger
)
from src.schemas.bill_schemas import (
    InventoryAdjustmentCreate, InventoryAdjustmentUpdate, InventoryAdjustmentResponse, InventoryAdjustmentListResponse
)
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/inventory-adjustments", tags=["Inventory Adjustments"])


@router.post("", response_model=InventoryAdjustmentResponse, status_code=status.HTTP_201_CREATED)
def create_inventory_adjustment(
    payload: InventoryAdjustmentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))  # Reusing invoice:create permission for now
):
    # Verify products belong to tenant
    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

    db_lines = []
    for line in payload.line_items:
        total_cost = (line.quantity_change * line.unit_cost) if line.unit_cost else None
        
        db_line = InventoryAdjustmentLine(
            product_id=line.product_id,
            quantity_change=line.quantity_change,
            unit_cost=line.unit_cost,
            total_cost=total_cost
        )
        db_lines.append(db_line)

    adjustment = InventoryAdjustment(
        tenant_id=tenant_id,
        adjustment_number=payload.adjustment_number,
        adjustment_date=payload.adjustment_date,
        status="DRAFT",
        reason=payload.reason,
        lines=db_lines
    )

    db.add(adjustment)
    db.commit()
    db.refresh(adjustment)
    return adjustment


@router.get("", response_model=List[InventoryAdjustmentListResponse])
def list_inventory_adjustments(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None
    ).offset(offset).limit(limit).all()

    response = []
    for adj in results:
        response.append(InventoryAdjustmentListResponse(
            id=adj.id,
            adjustment_number=adj.adjustment_number,
            adjustment_date=adj.adjustment_date,
            status=adj.status,
            created_at=adj.created_at
        ))
    return response


@router.get("/{id}", response_model=InventoryAdjustmentResponse)
def get_inventory_adjustment(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    adjustment = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None
    ).first()
    if not adjustment:
        raise HTTPException(status_code=404, detail="Inventory Adjustment not found in this company context.")
    return adjustment


@router.put("/{id}", response_model=InventoryAdjustmentResponse)
def update_inventory_adjustment(
    id: uuid.UUID,
    payload: InventoryAdjustmentUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    adjustment = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None
    ).first()
    if not adjustment:
        raise HTTPException(status_code=404, detail="Inventory Adjustment not found in this company context.")

    if adjustment.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft inventory adjustments can be modified.")

    # Verify products belong to tenant
    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

    # Update header fields
    if payload.adjustment_number:
        adjustment.adjustment_number = payload.adjustment_number
    if payload.adjustment_date:
        adjustment.adjustment_date = payload.adjustment_date
    if payload.reason is not None:
        adjustment.reason = payload.reason

    # Update line items
    if payload.line_items is not None:
        db.query(InventoryAdjustmentLine).filter(InventoryAdjustmentLine.adjustment_id == id).delete()
        
        db_lines = []
        for line in payload.line_items:
            total_cost = (line.quantity_change * line.unit_cost) if line.unit_cost else None
            
            db_line = InventoryAdjustmentLine(
                adjustment_id=adjustment.id,
                product_id=line.product_id,
                quantity_change=line.quantity_change,
                unit_cost=line.unit_cost,
                total_cost=total_cost
            )
            db_lines.append(db_line)
        
        adjustment.lines = db_lines

    db.commit()
    db.refresh(adjustment)
    return adjustment


@router.post("/{id}/confirm", response_model=InventoryAdjustmentResponse)
def confirm_inventory_adjustment(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    adjustment = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None
    ).first()
    if not adjustment:
        raise HTTPException(status_code=404, detail="Inventory Adjustment not found in this company context.")

    if adjustment.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft inventory adjustments can be confirmed.")

    # Create ledger entries for inventory adjustments
    resolver = AccountResolver(db, tenant_id)
    
    # For each line, create appropriate ledger entries
    journal_lines = []
    stock_ledger_entries = []
    for line in adjustment.lines:
        # Get or create inventory asset account for this product
        # In a real implementation, this would be more sophisticated
        inventory_account_id = resolver.resolve(f"assets.inventory.{line.product_id}")
        adjustment_account_id = resolver.resolve("inventory_adjustment")
        
        if line.quantity_change > 0:
            # Inventory increase - debit inventory, credit adjustment account
            journal_lines.append(JournalLine(
                account_id=inventory_account_id,
                amount=line.total_cost,
                direction="DEBIT",
                narration=f"Inventory increase for product {line.product_id}"
            ))
            journal_lines.append(JournalLine(
                account_id=adjustment_account_id,
                amount=line.total_cost,
                direction="CREDIT",
                narration=f"Inventory adjustment for product {line.product_id}"
            ))
            
            # Create stock ledger entry for stock-in
            stock_ledger_entries.append(StockLedger(
                tenant_id=tenant_id,
                product_id=line.product_id,
                quantity=line.quantity_change,  # positive for stock-in
                balance_quantity=0,  # Will be calculated properly in a real system
                reference_type="INVENTORY_ADJUSTMENT",
                reference_id=adjustment.id,
                rate=line.unit_cost
            ))
        else:
            # Inventory decrease - debit adjustment account, credit inventory
            journal_lines.append(JournalLine(
                account_id=adjustment_account_id,
                amount=abs(line.total_cost),
                direction="DEBIT",
                narration=f"Inventory decrease for product {line.product_id}"
            ))
            journal_lines.append(JournalLine(
                account_id=inventory_account_id,
                amount=abs(line.total_cost),
                direction="CREDIT",
                narration=f"Inventory adjustment for product {line.product_id}"
            ))
            
            # Create stock ledger entry for stock-out
            stock_ledger_entries.append(StockLedger(
                tenant_id=tenant_id,
                product_id=line.product_id,
                quantity=line.quantity_change,  # negative for stock-out
                balance_quantity=0,  # Will be calculated properly in a real system
                reference_type="INVENTORY_ADJUSTMENT",
                reference_id=adjustment.id,
                rate=line.unit_cost
            ))

    if journal_lines:
        journal_entry = JournalEntry(
            tenant_id=tenant_id,
            entry_date=adjustment.adjustment_date,
            reference_number=adjustment.adjustment_number,
            description=f"Inventory adjustment: {adjustment.reason or 'No reason provided'}",
            source_type="INVENTORY_ADJUSTMENT",
            source_id=adjustment.id,
            lines=journal_lines
        )
        db.add(journal_entry)
    
    # Add stock ledger entries
    for stock_entry in stock_ledger_entries:
        db.add(stock_entry)

    adjustment.status = "CONFIRMED"
    if journal_lines:
        affected = {line.account_id for line in journal_lines}
        update_account_balances(db, tenant_id, affected)
    db.commit()
    db.refresh(adjustment)
    return adjustment


@router.post("/{id}/cancel", response_model=InventoryAdjustmentResponse)
def cancel_inventory_adjustment(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    adjustment = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None
    ).first()
    if not adjustment:
        raise HTTPException(status_code=404, detail="Inventory Adjustment not found.")

    if adjustment.status in ("CONFIRMED", "CANCELLED"):
        raise HTTPException(status_code=400, detail="Cannot cancel confirmed or already cancelled inventory adjustments.")

    adjustment.status = "CANCELLED"
    db.commit()
    db.refresh(adjustment)
    return adjustment