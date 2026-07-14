from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal
from datetime import date
from sqlalchemy import func

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    InventoryAdjustment, InventoryAdjustmentLine, Product, JournalEntry, JournalLine, StockLedger
)
from src.schemas.bill_schemas import (
    InventoryAdjustmentCreate, InventoryAdjustmentUpdate, InventoryAdjustmentResponse, InventoryAdjustmentListResponse
)
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances
from src.domains.inventory.services import (
    resolve_default_warehouse_id,
    resolve_reversal_warehouse_id,
    get_warehouse_stock,
    get_stock_balance_after,
)
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/inventory-adjustments", tags=["Inventory Adjustments"])


@router.post("", response_model=InventoryAdjustmentResponse, status_code=status.HTTP_201_CREATED)
def create_inventory_adjustment(
    payload: InventoryAdjustmentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust"))
):
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.adjustment_date)
    product_ids = [line.product_id for line in payload.line_items]
    if not product_ids:
        raise HTTPException(status_code=400, detail="At least one adjustment line is required.")
    if len(product_ids) != len(set(product_ids)):
        raise HTTPException(status_code=400, detail="Each product can appear only once in an inventory adjustment.")
    if db.query(InventoryAdjustment.id).filter(
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.adjustment_number == payload.adjustment_number,
        InventoryAdjustment.deleted_at == None,
    ).first():
        raise HTTPException(status_code=400, detail="Adjustment number already exists in this company.")
    # Verify products belong to tenant
    products = {}
    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")
        products[line.product_id] = product

    db_lines = []
    for line in payload.line_items:
        unit_cost = line.unit_cost if line.unit_cost is not None else products[line.product_id].purchase_price
        if unit_cost is None or unit_cost <= 0:
            raise HTTPException(status_code=400, detail=f"A positive unit cost is required for {products[line.product_id].name}.")
        if line.quantity_change == 0:
            raise HTTPException(status_code=400, detail="Quantity change cannot be zero.")
        total_cost = abs(line.quantity_change) * unit_cost
        
        db_line = InventoryAdjustmentLine(
            product_id=line.product_id,
            quantity_change=line.quantity_change,
            unit_cost=unit_cost,
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
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view"))
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
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view"))
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
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust"))
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

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.adjustment_date or adjustment.adjustment_date)
    candidate_lines = payload.line_items or []
    product_ids = [line.product_id for line in candidate_lines]
    if len(product_ids) != len(set(product_ids)):
        raise HTTPException(status_code=400, detail="Each product can appear only once in an inventory adjustment.")
    # Verify products belong to tenant
    for line in candidate_lines:
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
            product = db.query(Product).filter(
                Product.id == line.product_id, Product.tenant_id == tenant_id
            ).first()
            unit_cost = line.unit_cost if line.unit_cost is not None else product.purchase_price
            if unit_cost is None or unit_cost <= 0:
                raise HTTPException(status_code=400, detail=f"A positive unit cost is required for {product.name}.")
            if line.quantity_change == 0:
                raise HTTPException(status_code=400, detail="Quantity change cannot be zero.")
            total_cost = abs(line.quantity_change) * unit_cost
            
            db_line = InventoryAdjustmentLine(
                adjustment_id=adjustment.id,
                product_id=line.product_id,
                quantity_change=line.quantity_change,
                unit_cost=unit_cost,
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
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:finalize"))
):
    adjustment = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None
    ).with_for_update().first()
    if not adjustment:
        raise HTTPException(status_code=404, detail="Inventory Adjustment not found in this company context.")

    if adjustment.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft inventory adjustments can be confirmed.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, adjustment.adjustment_date)
    # Create ledger entries for inventory adjustments
    resolver = AccountResolver(db, tenant_id)
    
    # For each line, create appropriate ledger entries
    journal_lines = []
    stock_ledger_entries = []
    for line in adjustment.lines:
        if line.total_cost is None or line.total_cost <= 0:
            raise HTTPException(status_code=400, detail=f"Total cost must be positive for product {line.product_id}.")
        
        # Inventory valuation is controlled through the shared inventory ledger;
        # product-level quantities remain in the stock ledger.
        inventory_account_id = resolver.resolve("assets.inventory")
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

        # Update product current_stock
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id
        ).with_for_update().first()
        if product:
            current_stock = product.current_stock or Decimal("0")
            warehouse_id = resolve_default_warehouse_id(db, tenant_id)
            location_stock = get_warehouse_stock(
                db, tenant_id, warehouse_id, line.product_id
            )
            effective_stock = location_stock if location_stock is not None else current_stock
            if line.quantity_change < 0 and effective_stock < abs(line.quantity_change):
                raise HTTPException(
                    status_code=400,
                    detail=f"Insufficient stock for {product.name} in the default warehouse. Available: {effective_stock}, reduction: {abs(line.quantity_change)}",
                )
            product.current_stock = current_stock + line.quantity_change
            balance_after = get_stock_balance_after(
                db, tenant_id, warehouse_id, line.product_id,
                line.quantity_change, product.current_stock,
            )
            # Create stock ledger entry
            stock_ledger_entries.append(StockLedger(
                tenant_id=tenant_id,
                product_id=line.product_id,
                warehouse_id=warehouse_id,
                quantity=line.quantity_change,
                balance_quantity=balance_after,
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
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:finalize"))
):
    adjustment = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None
    ).with_for_update().first()
    if not adjustment:
        raise HTTPException(status_code=404, detail="Inventory Adjustment not found.")

    if adjustment.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Inventory adjustment is already cancelled.")

    if adjustment.status == "CONFIRMED":
        from src.domains.accounting.period_lock import validate_period_open
        validate_period_open(db, tenant_id, adjustment.adjustment_date)
        # Preserve the original entry and add an explicit reversal.
        original_je = db.query(JournalEntry).filter(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.source_type == "INVENTORY_ADJUSTMENT",
            JournalEntry.source_id == adjustment.id,
        ).first()
        if original_je:
            # Reverse: swap DEBIT/CREDIT for each line
            reversal_lines = []
            for line in original_je.lines:
                reversal_lines.append(JournalLine(
                    account_id=line.account_id,
                    amount=line.amount,
                    direction="CREDIT" if line.direction == "DEBIT" else "DEBIT",
                    narration=f"Reversal: {line.narration}"
                ))
            reversal_entry = JournalEntry(
                tenant_id=tenant_id,
                entry_date=adjustment.adjustment_date,
                reference_number=f"REV-{adjustment.adjustment_number}",
                description=f"Reversal of inventory adjustment {adjustment.adjustment_number}",
                source_type="INVENTORY_ADJUSTMENT_REVERSAL",
                source_id=adjustment.id,
                lines=reversal_lines
            )
            db.add(reversal_entry)
            db.flush()
            update_account_balances(db, tenant_id, {line.account_id for line in reversal_lines})

        # Reverse stock changes: update product.current_stock
        for line in adjustment.lines:
            product = db.query(Product).filter(
                Product.id == line.product_id,
                Product.tenant_id == tenant_id
            ).with_for_update().first()
            if product:
                current_stock = product.current_stock or Decimal("0")
                warehouse_id = resolve_reversal_warehouse_id(
                    db,
                    tenant_id,
                    "INVENTORY_ADJUSTMENT",
                    adjustment.id,
                    line.product_id,
                )
                location_stock = get_warehouse_stock(
                    db, tenant_id, warehouse_id, line.product_id
                )
                effective_stock = location_stock if location_stock is not None else current_stock
                if line.quantity_change > 0 and effective_stock < line.quantity_change:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Cannot cancel: {product.name} stock from this increase has been consumed in its warehouse. Available: {effective_stock}, required: {line.quantity_change}",
                    )
                product.current_stock = current_stock - line.quantity_change
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    -line.quantity_change, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    quantity=-line.quantity_change,
                    balance_quantity=balance_after,
                    reference_type="INVENTORY_ADJUSTMENT_REVERSAL",
                    reference_id=adjustment.id,
                    rate=line.unit_cost
                ))

    adjustment.status = "CANCELLED"
    db.commit()
    db.refresh(adjustment)
    return adjustment
