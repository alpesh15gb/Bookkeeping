"""Complete vendor-bill reversal used by public PUT/DELETE corrections."""

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission, get_current_user
from src.core.database import get_db_session
from src.domains.accounting.auto_post import link_cancel_reversal
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, commit_ledger_draft
from src.domains.inventory.services import get_stock_balance_after, get_warehouse_stock
from src.domains.taxation.filing_lock import ensure_gst_period_mutable, GSTPeriodFiledError
from src.infrastructure.database.models import (
    Bill,
    BillPayment,
    BillPaymentAllocation,
    Product,
    PurchaseReturn,
    StockLedger,
    User,
)


def cancel_bill_for_direct_correction(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:delete")),
    current_user: User = Depends(get_current_user),
):
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None,
    ).with_for_update().first()
    if not bill:
        raise HTTPException(status_code=404, detail="Vendor Bill not found in this company context.")

    from src.domains.accounting.period_lock import validate_period_open

    validate_period_open(db, tenant_id, bill.issue_date)
    try:
        ensure_gst_period_mutable(db, tenant_id, bill.issue_date)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    if bill.status == "UNPAID":
        bill.status = "POSTED"
    if bill.status not in ("POSTED", "PARTIALLY_PAID"):
        raise HTTPException(status_code=409, detail="This bill is not in a reversible accounting state.")

    active_payment = db.query(BillPaymentAllocation.id).join(
        BillPayment, BillPayment.id == BillPaymentAllocation.payment_id
    ).filter(
        BillPaymentAllocation.bill_id == bill.id,
        BillPaymentAllocation.tenant_id == tenant_id,
        BillPayment.tenant_id == tenant_id,
        BillPayment.deleted_at == None,
        BillPayment.status != "CANCELLED",
    ).first()
    if active_payment:
        raise HTTPException(
            status_code=409,
            detail="Reverse applied vendor payment(s) before correcting this bill.",
        )

    active_return = db.query(PurchaseReturn.id).filter(
        PurchaseReturn.tenant_id == tenant_id,
        PurchaseReturn.bill_id == bill.id,
        PurchaseReturn.deleted_at == None,
        PurchaseReturn.status != "CANCELLED",
    ).first()
    if active_return:
        raise HTTPException(
            status_code=409,
            detail="Reverse the linked purchase return(s) before correcting this bill.",
        )

    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    cgst_account_id = resolver.resolve("cgst_input")
    sgst_account_id = resolver.resolve("sgst_input")
    igst_account_id = resolver.resolve("igst_input")
    utgst_account_id = resolver.resolve("utgst_input")
    cess_account_id = resolver.resolve("cess_input")
    round_off_account_id = resolver.resolve("round_off") if bill.round_off != 0 else None
    tds_account_id = (
        resolver.resolve("liability.tds")
        if bill.tds_amount and bill.tds_amount > 0
        else None
    )

    tax_total = (
        (bill.cgst_amount or Decimal("0"))
        + (bill.sgst_amount or Decimal("0"))
        + (bill.igst_amount or Decimal("0"))
        + (bill.utgst_amount or Decimal("0"))
        + (bill.cess_amount or Decimal("0"))
    )
    posting_subtotal = bill.subtotal if bill.itc_eligible else bill.subtotal + tax_total
    posting_cgst = bill.cgst_amount if bill.itc_eligible else Decimal("0")
    posting_sgst = bill.sgst_amount if bill.itc_eligible else Decimal("0")
    posting_igst = bill.igst_amount if bill.itc_eligible else Decimal("0")
    posting_utgst = bill.utgst_amount if bill.itc_eligible else Decimal("0")
    posting_cess = bill.cess_amount if bill.itc_eligible else Decimal("0")

    ledger_draft = LedgerPostingEngine.create_bill_reversal_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        cancel_date=bill.issue_date,
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=posting_subtotal,
        discount_total=bill.discount_total,
        shipping_charges=bill.shipping_charges or Decimal("0"),
        cgst_account_id=cgst_account_id,
        cgst_amount=posting_cgst,
        sgst_account_id=sgst_account_id,
        sgst_amount=posting_sgst,
        igst_account_id=igst_account_id,
        igst_amount=posting_igst,
        utgst_account_id=utgst_account_id,
        utgst_amount=posting_utgst,
        cess_account_id=cess_account_id,
        cess_amount=posting_cess,
        round_off_account_id=round_off_account_id,
        round_off_amount=bill.round_off,
        tds_account_id=tds_account_id,
        tds_amount=bill.tds_amount or Decimal("0"),
    )
    reversal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)
    link_cancel_reversal(db, tenant_id, "BILL", bill.id, reversal_entry, current_user.id)

    stock_moves = db.query(StockLedger).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == "BILL",
        StockLedger.reference_id == bill.id,
    ).all()
    for move in stock_moves:
        if move.reversal_movement_id is not None:
            raise HTTPException(status_code=409, detail="This bill stock movement has already been reversed.")
        product = db.query(Product).filter(
            Product.id == move.product_id,
            Product.tenant_id == tenant_id,
        ).with_for_update().first()
        if not product:
            raise HTTPException(status_code=409, detail="A product referenced by this bill no longer exists.")

        remove_quantity = move.quantity
        available = product.current_stock or Decimal("0")
        warehouse_available = get_warehouse_stock(
            db, tenant_id, move.warehouse_id, move.product_id
        )
        effective_available = warehouse_available if warehouse_available is not None else available
        if effective_available < remove_quantity:
            raise HTTPException(
                status_code=409,
                detail=(
                    f"Cannot correct bill {bill.bill_number}: purchased stock for "
                    f"{product.name} has already been consumed. Reverse downstream "
                    "stock movements first."
                ),
            )

        product.current_stock = available - remove_quantity
        balance_after = get_stock_balance_after(
            db,
            tenant_id,
            move.warehouse_id,
            move.product_id,
            -remove_quantity,
            product.current_stock,
        )
        reversal_move = StockLedger(
            tenant_id=tenant_id,
            product_id=move.product_id,
            warehouse_id=move.warehouse_id,
            reference_type="BILL_REVERSAL",
            reference_id=bill.id,
            quantity=-remove_quantity,
            balance_quantity=balance_after,
            rate=move.rate,
            reverses_movement_id=move.id,
        )
        db.add(reversal_move)
        db.flush()
        move.reversal_movement_id = reversal_move.id
        move.reversed_by = current_user.id
        move.reversed_at = datetime.now(timezone.utc)

    bill.status = "CANCELLED"
    bill.amount_paid = Decimal("0.0000")
    bill.cancelled_at = datetime.now(timezone.utc)
    bill.cancelled_by = current_user.id
    db.commit()
    db.refresh(bill)
    return bill


def install_direct_bill_reversal() -> None:
    from src.api.v1 import bills as bill_api

    bill_api.cancel_bill_route = cancel_bill_for_direct_correction
