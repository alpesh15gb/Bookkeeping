"""Complete invoice reversal adapter for direct Edit/Delete.

The legacy public `/cancel` handler had good stock-reversal linkage but did not
pass shipping/RCM arguments to the ledger reversal engine.  The older domain
helper handled shipping/RCM but did not stamp the stronger stock linkage
metadata.  This adapter combines both invariants and is used only internally by
the public PUT/DELETE contract.
"""

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission, get_current_user
from src.core.database import get_db_session
from src.domains.accounting.auto_post import link_cancel_reversal
from src.domains.accounting.services import (
    AccountResolver,
    LedgerPostingEngine,
    commit_ledger_draft,
)
from src.domains.inventory.services import (
    get_stock_balance_after,
    resolve_reversal_warehouse_id,
)
from src.domains.taxation.filing_lock import ensure_outward_period_mutable, GSTPeriodFiledError
from src.infrastructure.database.models import (
    Invoice,
    PaymentAllocation,
    Product,
    StockLedger,
    User,
)


def cancel_invoice_for_direct_correction(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
    current_user: User = Depends(get_current_user),
):
    """Reverse a financially posted invoice while preserving every fact.

    The caller may pass the normal Session or the direct-contract
    DeferredCommitSession.  With the latter, the final commit below becomes a
    flush so reversal + replacement remain one atomic transaction.
    """
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).with_for_update().first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    from src.domains.accounting.period_lock import validate_period_open

    validate_period_open(db, tenant_id, invoice.issue_date)
    try:
        ensure_outward_period_mutable(db, tenant_id, invoice.issue_date)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    if invoice.status == "SENT":
        invoice.status = "POSTED"
    if invoice.status not in ("POSTED", "PARTIALLY_PAID"):
        raise HTTPException(
            status_code=409,
            detail="This invoice is not in a reversible accounting state.",
        )

    if db.query(PaymentAllocation.id).filter(
        PaymentAllocation.invoice_id == invoice.id,
        PaymentAllocation.tenant_id == tenant_id,
    ).first():
        raise HTTPException(
            status_code=409,
            detail="Reverse applied receipt(s) before correcting this invoice.",
        )

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    round_off_account_id = resolver.resolve("round_off") if invoice.round_off != 0 else None

    # Reverse exactly what the original posting engine recorded, including
    # shipping income and reverse-charge behavior.
    ledger_draft = LedgerPostingEngine.create_invoice_reversal_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        cancel_date=invoice.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        discount_total=invoice.discount_total,
        shipping_charges=invoice.shipping_charges or Decimal("0"),
        cgst_account_id=cgst_account_id,
        cgst_amount=invoice.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=invoice.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=invoice.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=invoice.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=invoice.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=invoice.round_off,
        is_rcm=invoice.is_rcm,
    )
    reversal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)
    link_cancel_reversal(
        db,
        tenant_id,
        "INVOICE",
        invoice.id,
        reversal_entry,
        current_user.id,
    )

    # Restore only stock actually moved by this invoice.  Source-derived
    # invoices (for example from a delivery challan) have no INVOICE movement
    # and therefore cannot double-restore already delivered stock.
    stock_moves = db.query(StockLedger).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == "INVOICE",
        StockLedger.reference_id == invoice.id,
    ).all()
    for move in stock_moves:
        if move.reversal_movement_id is not None:
            raise HTTPException(
                status_code=409,
                detail="This invoice stock movement has already been reversed.",
            )
        product = db.query(Product).filter(
            Product.id == move.product_id,
            Product.tenant_id == tenant_id,
        ).with_for_update().first()
        if not product:
            raise HTTPException(
                status_code=409,
                detail="A product referenced by this invoice no longer exists.",
            )

        restore_quantity = -move.quantity
        product.current_stock = (product.current_stock or Decimal("0")) + restore_quantity
        warehouse_id = move.warehouse_id or resolve_reversal_warehouse_id(
            db,
            tenant_id,
            "INVOICE",
            invoice.id,
            move.product_id,
        )
        balance_after = get_stock_balance_after(
            db,
            tenant_id,
            warehouse_id,
            move.product_id,
            restore_quantity,
            product.current_stock,
        )
        reversal_move = StockLedger(
            tenant_id=tenant_id,
            product_id=move.product_id,
            warehouse_id=warehouse_id,
            reference_type="INVOICE_REVERSAL",
            reference_id=invoice.id,
            quantity=restore_quantity,
            balance_quantity=balance_after,
            rate=move.rate,
            reverses_movement_id=move.id,
        )
        db.add(reversal_move)
        db.flush()
        move.reversal_movement_id = reversal_move.id
        move.reversed_by = current_user.id
        move.reversed_at = datetime.now(timezone.utc)

    invoice.status = "CANCELLED"
    invoice.amount_paid = Decimal("0.0000")
    invoice.cancelled_at = datetime.now(timezone.utc)
    invoice.cancelled_by = current_user.id
    db.commit()
    db.refresh(invoice)
    return invoice


def install_direct_invoice_reversal() -> None:
    # Direct route handlers look up this module attribute at execution time, so
    # replacing the internal callable does not re-expose the removed /cancel
    # route and keeps the public API limited to POST/PUT/DELETE.
    from src.api.v1 import invoices as invoice_api

    invoice_api.cancel_invoice = cancel_invoice_for_direct_correction
