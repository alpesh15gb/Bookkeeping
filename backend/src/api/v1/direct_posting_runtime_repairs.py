"""Focused runtime repairs for the direct-posting public contract.

These hooks keep the user-facing API limited to Create/Edit/Delete while
preserving append-only accounting history.  They deliberately do not weaken
journal/stock immutability or re-introduce Draft/Finalize/Cancel workflows.
"""

import uuid

from fastapi import Depends, Response, status
from sqlalchemy import event
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission
from src.core.database import get_db_session
from src.infrastructure.database.models import JournalEntry

_INSTALLED = False


def _drop_routes(router, *, contains: str, method: str) -> None:
    """Remove all matching methods regardless of legacy path-parameter name."""
    method = method.upper()
    kept = []
    for route in router.routes:
        methods = set(getattr(route, "methods", set()) or set())
        path = getattr(route, "path", "") or ""
        if contains in path and method in methods:
            remaining = methods - {method}
            if remaining:
                route.methods = remaining
                kept.append(route)
            continue
        kept.append(route)
    router.routes[:] = kept


def _capture_correction_context(session: Session, flush_context) -> None:
    """Remember the original ledger fact after an internal reversal flush."""
    if not session.info.get("_defer_idempotency_mark"):
        return
    for obj in list(session.new):
        if not isinstance(obj, JournalEntry):
            continue
        if obj.source_type == "JOURNAL_REVERSAL":
            # source_id is the original manual/contra journal id.
            session.info["_pending_manual_original_journal_id"] = obj.source_id
        elif obj.source_type == "INVENTORY_ADJUSTMENT_REVERSAL":
            # source_id is the original inventory-adjustment document id.
            session.info["_pending_inventory_original_adjustment_id"] = obj.source_id


def _link_replacement_before_insert(session: Session, flush_context, instances) -> None:
    """Stamp original_transaction_id before a replacement journal is INSERTed.

    original_transaction_id is immutable after insertion at both ORM and
    PostgreSQL trigger layers.  Linking here keeps that invariant intact.
    """
    pending_manual = session.info.get("_pending_manual_original_journal_id")
    pending_inventory = session.info.get("_pending_inventory_original_adjustment_id")

    for obj in list(session.new):
        if not isinstance(obj, JournalEntry):
            continue

        if pending_manual and obj.source_type in ("MANUAL", "CONTRA"):
            if obj.id is None:
                obj.id = uuid.uuid4()
            original = session.get(JournalEntry, pending_manual)
            if original is not None:
                obj.original_transaction_id = original.id
                original.replacement_transaction_id = obj.id
            session.info.pop("_pending_manual_original_journal_id", None)
            pending_manual = None

        if pending_inventory and obj.source_type == "INVENTORY_ADJUSTMENT":
            original = session.query(JournalEntry).filter(
                JournalEntry.tenant_id == obj.tenant_id,
                JournalEntry.source_type == "INVENTORY_ADJUSTMENT",
                JournalEntry.source_id == pending_inventory,
            ).first()
            if original is not None:
                if obj.id is None:
                    obj.id = uuid.uuid4()
                obj.original_transaction_id = original.id
                original.replacement_transaction_id = obj.id
            session.info.pop("_pending_inventory_original_adjustment_id", None)
            pending_inventory = None


def _install_idempotency_preview_exemption() -> None:
    import src.api.idempotency_middleware as idem

    if getattr(idem, "_direct_preview_exemption_installed", False):
        return
    original = idem._requires_mandatory_key

    def requires_mandatory_key(method: str, path: str) -> bool:
        # Preview/calculation POSTs do not mutate financial or stock facts.
        if method.upper() == "POST" and path.rstrip("/").endswith("/preview"):
            return False
        return original(method, path)

    idem._requires_mandatory_key = requires_mandatory_key
    idem._direct_preview_exemption_installed = True


def _install_note_delete_routes() -> None:
    from src.api.v1 import invoices as invoice_api
    from src.api.v1.direct_posting_contract_ext import (
        direct_delete_credit_note,
        direct_delete_debit_note,
    )

    # The legacy draft-only DELETE routes were registered before the direct
    # handlers and therefore won route resolution. Remove every DELETE variant
    # first, then add exactly one direct correction route for each note type.
    _drop_routes(invoice_api.router, contains="/credit-notes/", method="DELETE")
    _drop_routes(invoice_api.router, contains="/debit-notes/", method="DELETE")
    invoice_api.router.add_api_route(
        "/credit-notes/{id}",
        direct_delete_credit_note,
        methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )
    invoice_api.router.add_api_route(
        "/debit-notes/{id}",
        direct_delete_debit_note,
        methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )


def _install_delivery_conversion_route() -> None:
    from src.api.v1 import delivery_challans as delivery_api
    from src.api.v1.direct_posting_contract import DeferredCommitSession, _unwrap
    from src.domains.accounting.auto_post import auto_post_invoice
    from src.schemas.document import InvoiceResponse

    def convert_delivery_challan_direct(
        id: uuid.UUID,
        db: Session = Depends(get_db_session),
        tenant_id: uuid.UUID = Depends(enforce_permission("sales:convert")),
    ):
        # Reuse the existing conversion builder but defer its commit so the
        # source link and accounting journal land atomically. Stock already
        # moved when the challan was issued, hence move_stock=False.
        proxy = DeferredCommitSession(db)
        invoice = _unwrap(delivery_api.convert_delivery_challan_to_invoice)(
            id, proxy, tenant_id
        )
        if invoice.status == "DRAFT":
            auto_post_invoice(db, tenant_id, invoice, move_stock=False)
        db.commit()
        db.refresh(invoice)
        return invoice

    _drop_routes(
        delivery_api.router,
        contains="/convert-to-invoice",
        method="POST",
    )
    delivery_api.router.add_api_route(
        "/{id}/convert-to-invoice",
        convert_delivery_challan_direct,
        methods=["POST"],
        response_model=InvoiceResponse,
    )


def install_direct_posting_runtime_repairs() -> None:
    global _INSTALLED
    if _INSTALLED:
        return
    _INSTALLED = True

    # Register once on the shared SQLAlchemy Session class. The hooks only act
    # when the direct correction flow has established a pending reversal.
    event.listen(Session, "after_flush", _capture_correction_context)
    event.listen(Session, "before_flush", _link_replacement_before_insert)

    _install_idempotency_preview_exemption()
    _install_note_delete_routes()
    _install_delivery_conversion_route()
