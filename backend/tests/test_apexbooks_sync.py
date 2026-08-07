import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import jwt

from src.core.security import (
    ALGORITHM,
    Permissions,
    SECRET_KEY,
    create_access_token,
    get_password_hash,
)
from src.infrastructure.database.models import (
    Account,
    Contact,
    FinancialYear,
    GoodsReceipt,
    JournalEntry,
    JournalLine,
    Invoice,
    InvoiceLine,
    OfflineNumberAllocation,
    Payment,
    Product,
    Bill,
    BillLine,
    SalesOrder,
    DeliveryChallan,
    SalesReturn,
    PurchaseReturn,
    CreditNote,
    DebitNote,
    StockLedger,
    SyncEvent,
    Tenant,
    TenantMembership,
    User,
)


def _seed_sync_tenant(db_session):
    tenant = Tenant(
        id=uuid.uuid4(),
        legal_name="Sync Test Pvt Ltd",
        trade_name="Sync Test",
        gstin=f"27{uuid.uuid4().hex[:10].upper()}1Z5"[:15],
        pan="ABCDE1234F",
        tax_mode="GST_REGULAR",
        financial_year_start=date(2026, 4, 1),
    )
    db_session.add(tenant)

    user = User(
        id=uuid.uuid4(),
        email=f"sync-{uuid.uuid4().hex[:8]}@test.com",
        password_hash=get_password_hash("Test@1234"),
        full_name="Sync Tester",
    )
    db_session.add(user)
    db_session.add(
        TenantMembership(
            tenant_id=tenant.id,
            user_id=user.id,
            role="owner",
            is_active=True,
        ),
    )
    db_session.add(
        FinancialYear(
            id=uuid.uuid4(),
            tenant_id=tenant.id,
            name="2026-27",
            start_date=date(2026, 4, 1),
            end_date=date(2027, 3, 31),
            status="CURRENT",
            is_current=True,
            transaction_count=0,
            created_by=user.id,
        ),
    )

    cash = Account(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        code="1001",
        name="Cash",
        account_type="ASSET",
        account_group="Cash & Bank",
        opening_balance=Decimal("0"),
        current_balance=Decimal("0"),
        is_active=True,
    )
    revenue = Account(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        code="4001",
        name="Revenue",
        account_type="REVENUE",
        account_group="Income",
        opening_balance=Decimal("0"),
        current_balance=Decimal("0"),
        is_active=True,
    )
    db_session.add_all([cash, revenue])
    db_session.commit()
    return tenant, user, cash, revenue


def _sync_headers(user, tenant):
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": str(user.id),
            "tenant_id": str(tenant.id),
            "permissions": [Permissions.SYNC_WRITE, Permissions.SYNC_READ],
            "type": "access",
            "iat": now,
            "exp": now + timedelta(minutes=30),
        },
        SECRET_KEY,
        algorithm=ALGORITHM,
    )
    return {"Authorization": f"Bearer {token}"}


def _journal_event(tenant, cash, revenue, *, legacy=False, event_id=None):
    event_id = event_id or uuid.uuid4()
    line_amount = 18_000_000
    debit_line = {"account_id": str(cash.id), "narration": "Cash leg"}
    credit_line = {"account_id": str(revenue.id), "narration": "Revenue leg"}
    if legacy:
        debit_line.update({"direction": "DEBIT", "amount_micros": line_amount})
        credit_line.update({"direction": "CREDIT", "amount_micros": line_amount})
    else:
        debit_line.update({"direction": "DEBIT", "debit_micros": line_amount})
        credit_line.update({"direction": "CREDIT", "credit_micros": line_amount})

    return {
        "event_id": str(event_id),
        "company_id": str(tenant.id),
        "device_id": str(uuid.uuid4()),
        "aggregate_type": "journal",
        "aggregate_id": str(event_id),
        "event_type": "journal.posted",
        "event_version": 1,
        "occurred_at": "2026-07-27T10:00:00Z",
        "payload": {
            "entry_date": "2026-07-27",
            "reference_number": "JRN-SYNC-001",
            "voucher_number": "JRN-SYNC-001",
            "description": "Sync journal description",
            "narration": "Sync journal narration",
            "lines": [debit_line, credit_line],
        },
    }


def _sync_event(tenant, event_type, aggregate_type, payload, *, aggregate_id=None):
    aggregate_id = aggregate_id or uuid.uuid4()
    return {
        "event_id": str(uuid.uuid4()),
        "company_id": str(tenant.id),
        "device_id": str(uuid.uuid4()),
        "aggregate_type": aggregate_type,
        "aggregate_id": str(aggregate_id),
        "event_type": event_type,
        "event_version": 1,
        "occurred_at": "2026-07-27T10:00:00Z",
        "payload": payload,
    }


def test_sync_principal_accepts_existing_ui_token_with_tenant_header(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    event = _journal_event(tenant, cash, revenue)
    token = create_access_token(user_id=str(user.id), scopes=[Permissions.SYNC_WRITE])

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers={
            "Authorization": f"Bearer {token}",
            "X-Tenant-ID": str(tenant.id),
        },
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None


def test_sync_push_journal_posted_acknowledges_processes_and_deduplicates(
    client,
    db_session,
):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    headers = _sync_headers(user, tenant)
    event = _journal_event(tenant, cash, revenue)

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=headers,
    )

    assert response.status_code == 200
    ack = response.json()["acknowledgements"][0]
    assert ack["event_id"] == event["event_id"]
    assert ack["duplicate"] is False
    assert ack["error"] is None

    journal = db_session.query(JournalEntry).filter_by(source_id=uuid.UUID(event["aggregate_id"])).one()
    assert journal.reference_number == "JRN-SYNC-001"
    assert journal.description == "Sync journal narration"
    lines = db_session.query(JournalLine).filter_by(entry_id=journal.id).all()
    debit = sum(line.amount for line in lines if line.direction == "DEBIT")
    credit = sum(line.amount for line in lines if line.direction == "CREDIT")
    assert debit == credit == Decimal("1800.0000")

    duplicate = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=headers,
    )
    assert duplicate.status_code == 200
    assert duplicate.json()["acknowledgements"][0]["duplicate"] is True
    assert db_session.query(JournalEntry).filter_by(source_id=uuid.UUID(event["aggregate_id"])).count() == 1


def test_sync_push_accepts_legacy_direction_amount_micros_payload(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    event = _journal_event(tenant, cash, revenue, legacy=True)

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    ack = response.json()["acknowledgements"][0]
    assert ack["error"] is None
    journal = db_session.query(JournalEntry).filter_by(source_id=uuid.UUID(event["aggregate_id"])).one()
    assert journal.reference_number == "JRN-SYNC-001"


def test_sync_push_journal_draft_update_post_and_reversal_lifecycle(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    headers = _sync_headers(user, tenant)
    created = _journal_event(tenant, cash, revenue)
    created["event_type"] = "journal.created"
    journal_id = created["aggregate_id"]

    updated = _journal_event(tenant, cash, revenue)
    updated["event_type"] = "journal.updated"
    updated["aggregate_id"] = journal_id
    updated["payload"]["description"] = "Edited draft"

    for event in (created, updated):
        response = client.post(
            "/api/v1/apexbooks/sync/push",
            json={"events": [event]},
            headers=headers,
        )
        assert response.status_code == 200
        assert response.json()["acknowledgements"][0]["error"] is None
    assert db_session.query(JournalEntry).filter_by(
        source_id=uuid.UUID(journal_id),
    ).count() == 0

    posted = _journal_event(tenant, cash, revenue)
    posted["aggregate_id"] = journal_id
    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [posted]},
        headers=headers,
    )
    assert response.json()["acknowledgements"][0]["error"] is None
    assert db_session.query(JournalEntry).filter_by(
        source_id=uuid.UUID(journal_id),
    ).count() == 1

    replay = _journal_event(tenant, cash, revenue)
    replay["aggregate_id"] = journal_id
    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [replay]},
        headers=headers,
    )
    assert response.json()["acknowledgements"][0]["error"] is None
    assert db_session.query(JournalEntry).filter_by(
        source_id=uuid.UUID(journal_id),
    ).count() == 1

    reversal = _journal_event(tenant, cash, revenue)
    reversal["event_type"] = "journal.reversed"
    reversal["payload"]["source_type"] = "JOURNAL_REVERSAL"
    reversal["payload"]["reversed_journal_id"] = journal_id
    debit_reversal = dict(reversal["payload"]["lines"][1])
    debit_reversal.pop("credit_micros", None)
    debit_reversal.update({"direction": "DEBIT", "debit_micros": 18_000_000})
    credit_reversal = dict(reversal["payload"]["lines"][0])
    credit_reversal.pop("debit_micros", None)
    credit_reversal.update({"direction": "CREDIT", "credit_micros": 18_000_000})
    reversal["payload"]["lines"] = [debit_reversal, credit_reversal]
    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [reversal]},
        headers=headers,
    )
    assert response.json()["acknowledgements"][0]["error"] is None
    assert db_session.query(JournalEntry).filter_by(
        source_type="JOURNAL_REVERSAL",
        source_id=uuid.UUID(journal_id),
    ).count() == 1


def test_sync_push_rejects_malformed_journal_and_pull_hides_unprocessed_event(
    client,
    db_session,
):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    event = _journal_event(tenant, cash, revenue)
    event["payload"]["lines"][0]["credit_micros"] = event["payload"]["lines"][0]["debit_micros"]

    headers = _sync_headers(user, tenant)
    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=headers,
    )

    assert response.status_code == 200
    ack = response.json()["acknowledgements"][0]
    assert ack["error"]
    assert "exactly one non-zero side" in ack["error"]
    stored_event = db_session.query(SyncEvent).filter_by(event_id=uuid.UUID(event["event_id"])).one()
    assert stored_event.processed is False
    assert db_session.query(JournalEntry).filter_by(source_id=uuid.UUID(event["aggregate_id"])).count() == 0

    pull = client.get("/api/v1/apexbooks/sync/pull", headers=headers)
    assert pull.status_code == 200
    assert pull.json()["events"] == []


def test_sync_push_rejects_cross_company_event_scope(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    event = _journal_event(tenant, cash, revenue)
    event["company_id"] = str(uuid.uuid4())

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 403
    assert (
        db_session.query(SyncEvent)
        .filter_by(event_id=uuid.UUID(event["event_id"]))
        .count()
        == 0
    )


def test_number_allocations_are_device_scoped_and_non_overlapping(
    client,
    db_session,
):
    tenant, user, _, _ = _seed_sync_tenant(db_session)
    headers = _sync_headers(user, tenant)
    first_device = uuid.uuid4()
    second_device = uuid.uuid4()

    first = client.post(
        "/api/v1/apexbooks/number-allocations",
        json={
            "device_id": str(first_device),
            "document_type": "INVOICE",
            "series": "INVOICE",
            "batch_size": 10,
        },
        headers=headers,
    )
    second = client.post(
        "/api/v1/apexbooks/number-allocations",
        json={
            "device_id": str(second_device),
            "document_type": "INVOICE",
            "series": "INVOICE",
            "batch_size": 10,
        },
        headers=headers,
    )

    assert first.status_code == second.status_code == 200
    first_body = first.json()
    second_body = second.json()
    assert first_body["to_num"] < second_body["from_num"]
    assert first_body["device_id"] == str(first_device)
    assert second_body["device_id"] == str(second_device)
    assert (
        db_session.query(OfflineNumberAllocation)
        .filter_by(tenant_id=tenant.id)
        .count()
        == 2
    )

    repeated = client.post(
        "/api/v1/apexbooks/number-allocations",
        json={
            "device_id": str(first_device),
            "document_type": "INVOICE",
            "series": "INVOICE",
            "batch_size": 10,
        },
        headers=headers,
    )
    assert repeated.json()["allocation_id"] == first_body["allocation_id"]


def test_reference_snapshot_provisions_contact_ledgers_and_products(
    client,
    db_session,
):
    tenant, user, _, _ = _seed_sync_tenant(db_session)
    contact = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Snapshot Customer",
        contact_type="BOTH",
        registration_type="CONSUMER",
        is_active=True,
    )
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Offline Widget",
        sku="OFF-1",
        hsn_sac="84713010",
        product_type="GOODS",
        uom="PCS",
        sales_price=Decimal("125.50"),
        purchase_price=Decimal("100.00"),
        gst_rate=Decimal("18.00"),
        opening_stock=Decimal("3"),
        current_stock=Decimal("3"),
        reorder_level=Decimal("1"),
        is_active=True,
    )
    db_session.add_all([contact, product])
    db_session.commit()

    response = client.get(
        "/api/v1/apexbooks/reference-snapshot",
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    body = response.json()
    returned_contact = next(row for row in body["contacts"] if row["id"] == str(contact.id))
    assert returned_contact["receivable_account_id"]
    assert returned_contact["payable_account_id"]
    account_ids = {row["id"] for row in body["accounts"]}
    assert returned_contact["receivable_account_id"] in account_ids
    assert returned_contact["payable_account_id"] in account_ids
    returned_product = next(row for row in body["products"] if row["id"] == str(product.id))
    assert returned_product["sales_price"] == "125.5000"
    assert returned_product["gst_rate"] == "18.00"


def test_money_transaction_sync_posts_balanced_receipt_ledger(
    client,
    db_session,
):
    tenant, user, cash, _ = _seed_sync_tenant(db_session)
    contact = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Offline Receipt Customer",
        contact_type="CUSTOMER",
        registration_type="CONSUMER",
        is_active=True,
    )
    db_session.add(contact)
    db_session.commit()
    payment_id = uuid.uuid4()
    event = _sync_event(
        tenant,
        "money_transaction.posted",
        "money_transaction",
        {
            "kind": "receipt",
            "payment_date": "2026-07-27",
            "contact_id": str(contact.id),
            "payment_mode": "CASH",
            "account_id": str(cash.id),
            "amount_micros": 12_345_600,
            "reference": "OFF-RCP-1",
            "narration": "Offline customer receipt",
        },
        aggregate_id=payment_id,
    )

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None
    payment = db_session.query(Payment).filter_by(id=payment_id).one()
    assert payment.amount == Decimal("1234.5600")
    journal = db_session.query(JournalEntry).filter_by(source_id=payment_id).one()
    lines = db_session.query(JournalLine).filter_by(entry_id=journal.id).all()
    debit = sum(line.amount for line in lines if line.direction == "DEBIT")
    credit = sum(line.amount for line in lines if line.direction == "CREDIT")
    assert debit == credit == Decimal("1234.5600")


def test_purchase_receipt_sync_updates_stock_and_posts_balanced_ledger(
    client,
    db_session,
):
    tenant, user, _, _ = _seed_sync_tenant(db_session)
    supplier = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Offline Supplier",
        contact_type="VENDOR",
        registration_type="REGULAR",
        is_active=True,
    )
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Received Widget",
        sku="GRN-1",
        hsn_sac="84713010",
        product_type="GOODS",
        uom="PCS",
        sales_price=Decimal("100"),
        purchase_price=Decimal("60"),
        gst_rate=Decimal("18"),
        opening_stock=Decimal("2"),
        current_stock=Decimal("2"),
        reorder_level=Decimal("1"),
        is_active=True,
    )
    db_session.add_all([supplier, product])
    db_session.commit()
    receipt_id = uuid.uuid4()
    event = _sync_event(
        tenant,
        "purchase_receipt.posted",
        "purchase_receipt",
        {
            "receipt_date": "2026-07-27",
            "supplier_id": str(supplier.id),
            "reference_number": "OFF-GRN-1",
            "lines": [
                {
                    "item_id": str(product.id),
                    "quantity_micros": 30_000,
                    "unit_cost_micros": 600_000,
                },
            ],
        },
        aggregate_id=receipt_id,
    )

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None
    receipt = db_session.query(GoodsReceipt).filter_by(id=receipt_id).one()
    assert receipt.status == "CONFIRMED"
    db_session.refresh(product)
    assert product.current_stock == Decimal("5.0000")
    movement = db_session.query(StockLedger).filter_by(
        reference_type="GOODS_RECEIPT",
        reference_id=receipt_id,
    ).one()
    assert movement.quantity == Decimal("3.0000")
    journal = db_session.query(JournalEntry).filter_by(
        source_type="GOODS_RECEIPT",
        source_id=receipt_id,
    ).one()
    lines = db_session.query(JournalLine).filter_by(entry_id=journal.id).all()
    assert sum(line.amount for line in lines if line.direction == "DEBIT") == sum(
        line.amount for line in lines if line.direction == "CREDIT"
    ) == Decimal("180.00")


def test_allocated_offline_invoice_validates_totals_and_posts_ledger(
    client,
    db_session,
):
    tenant, user, _, _ = _seed_sync_tenant(db_session)
    contact = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Offline Invoice Customer",
        contact_type="CUSTOMER",
        registration_type="REGULAR",
        gstin="27ABCDE1234F1Z5",
        state_code="27",
        is_active=True,
    )
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Taxed Widget",
        sku="TAX-1",
        hsn_sac="84713010",
        product_type="GOODS",
        uom="PCS",
        sales_price=Decimal("100.00"),
        purchase_price=Decimal("60.00"),
        gst_rate=Decimal("18.00"),
        opening_stock=Decimal("10"),
        current_stock=Decimal("10"),
        reorder_level=Decimal("1"),
        is_active=True,
    )
    db_session.add_all([contact, product])
    db_session.commit()
    headers = _sync_headers(user, tenant)
    device_id = uuid.uuid4()
    allocation = client.post(
        "/api/v1/apexbooks/number-allocations",
        json={
            "device_id": str(device_id),
            "document_type": "INVOICE",
            "series": "INVOICE",
            "batch_size": 5,
        },
        headers=headers,
    ).json()
    number = allocation["from_num"]
    display_number = (
        f"{allocation['prefix']}"
        f"{number:0{allocation['padding_digits']}d}"
        f"{allocation['suffix'] or ''}"
    )
    invoice_id = uuid.uuid4()
    event = _sync_event(
        tenant,
        "invoice.posted",
        "invoice",
        {
            "kind": "sale",
            "number": number,
            "invoice_number": display_number,
            "allocation_id": allocation["allocation_id"],
            "financial_year_id": allocation["financial_year_id"],
            "invoice_date": "2026-07-27",
            "due_date": "2026-08-10",
            "party_id": str(contact.id),
            "place_of_supply_state_code": "27",
            "subtotal_micros": 10_000_000,
            "tax_micros": 1_800_000,
            "total_micros": 11_800_000,
            "lines": [
                {
                    "item_id": str(product.id),
                    "quantity_micros": 10_000,
                    "rate_micros": 10_000_000,
                    "discount_micros": 0,
                    "line_total_micros": 10_000_000,
                    "tax_rate_basis_points": 1_800,
                    "tax_micros": 1_800_000,
                },
            ],
        },
        aggregate_id=invoice_id,
    )
    event["device_id"] = str(device_id)

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=headers,
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None
    invoice = db_session.query(Invoice).filter_by(id=invoice_id).one()
    assert invoice.status == "POSTED"
    assert invoice.total == Decimal("1180.0000")
    journal = db_session.query(JournalEntry).filter_by(
        source_type="INVOICE",
        source_id=invoice_id,
    ).one()
    lines = db_session.query(JournalLine).filter_by(entry_id=journal.id).all()
    assert sum(line.amount for line in lines if line.direction == "DEBIT") == sum(
        line.amount for line in lines if line.direction == "CREDIT"
    )


def test_sync_purchase_invoice_posted(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    supplier = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Purchase Invoice Supplier",
        contact_type="VENDOR",
        registration_type="CONSUMER",
        is_active=True,
    )
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Purchased Item",
        sku="PI-1",
        hsn_sac="84713010",
        product_type="GOODS",
        uom="PCS",
        sales_price=Decimal("150"),
        purchase_price=Decimal("120"),
        gst_rate=Decimal("18"),
        opening_stock=Decimal("10"),
        current_stock=Decimal("10"),
        reorder_level=Decimal("1"),
        is_active=True,
    )
    db_session.add_all([supplier, product])
    db_session.commit()

    bill_id = uuid.uuid4()
    event = _sync_event(
        tenant,
        "purchase_invoice.posted",
        "purchase_invoice",
        {
            "invoice_number": "BILL-SYNC-100",
            "invoice_date": "2026-07-27",
            "supplier_id": str(supplier.id),
            "party_id": str(supplier.id),
            "supplier_name": supplier.name,
            "total_paise": 12000,
            "subtotal_micros": 1200000,
            "total_micros": 1200000,
            "lines": [
                {
                    "item_id": str(product.id),
                    "product_name": product.name,
                    "quantity": "100",
                    "quantity_micros": 1000000,
                    "unit_price_paise": 120,
                    "rate_micros": 12000,
                    "line_total_micros": 1200000,
                }
            ],
        },
        aggregate_id=bill_id,
    )

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None
    bill = db_session.query(Bill).filter_by(id=bill_id).one()
    assert bill.bill_number == "BILL-SYNC-100"
    journal = db_session.query(JournalEntry).filter_by(
        source_type="BILL",
        source_id=bill_id,
    ).one()
    assert journal.is_locked is True


def test_sync_purchase_invoice_tax_split_by_supplier_state(client, db_session):
    """Regression: an offline-synced purchase invoice must split CGST/SGST vs
    IGST by comparing the supplier's state to the company's origin state, not by
    assuming interstate (IGST) for every import (the pre-fix behaviour when the
    client omitted place_of_supply_state_code, which defaulted to "00").

    Seeded tenant origin state is "27" (Maharashtra, from GSTIN prefix).
    """
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    # Give the tenant a valid Maharashtra GSTIN so resolve_origin_state_code
    # resolves its origin state to "27" (the seeded random-hex GSTIN is invalid,
    # which would fall back to "36").
    tenant.gstin = "27AAPFU0939F1ZV"
    db_session.commit()
    subtotal_micros = 1_000_000  # 100.00 (₹1 = 10_000 micros)
    tax_micros = 180_000         # 18.00

    cases = [
        ("27", 9, 9, 0),   # intra-state  -> CGST + SGST (18/2)
        ("29", 0, 0, 18),  # inter-state  -> IGST (18)
    ]

    for supplier_state, exp_cgst, exp_sgst, exp_igst in cases:
        supplier = Contact(
            id=uuid.uuid4(),
            tenant_id=tenant.id,
            name=f"Supplier {supplier_state}",
            contact_type="VENDOR",
            registration_type="CONSUMER",
            state_code=supplier_state,
            is_active=True,
        )
        product = Product(
            id=uuid.uuid4(),
            tenant_id=tenant.id,
            name=f"Purchased Item {supplier_state}",
            sku=f"PI-{supplier_state}",
            hsn_sac="84713010",
            product_type="GOODS",
            uom="PCS",
            sales_price=Decimal("150"),
            purchase_price=Decimal("120"),
            gst_rate=Decimal("18"),
            opening_stock=Decimal("10"),
            current_stock=Decimal("10"),
            is_active=True,
        )
        db_session.add_all([supplier, product])
        db_session.commit()

        bill_id = uuid.uuid4()
        event = _sync_event(
            tenant,
            "purchase_invoice.posted",
            "purchase_invoice",
            {
                "invoice_number": f"BILL-SYNC-{supplier_state}",
                "invoice_date": "2026-07-27",
                "supplier_id": str(supplier.id),
                "party_id": str(supplier.id),
                "supplier_name": supplier.name,
                "total_paise": (subtotal_micros + tax_micros) // 100,
                "subtotal_micros": subtotal_micros,
                "tax_micros": tax_micros,
                "total_micros": subtotal_micros + tax_micros,
                "lines": [
                    {
                        "item_id": str(product.id),
                        "product_name": product.name,
                        "quantity": "100",
                        "quantity_micros": 1_000_000,
                        "unit_price_paise": 120,
                        "rate_micros": 12_000,
                        "line_total_micros": 1_200_000,
                    }
                ],
            },
            aggregate_id=bill_id,
        )

        response = client.post(
            "/api/v1/apexbooks/sync/push",
            json={"events": [event]},
            headers=_sync_headers(user, tenant),
        )

        assert response.status_code == 200, response.text
        assert response.json()["acknowledgements"][0]["error"] is None

        bill = db_session.query(Bill).filter_by(id=bill_id).one()
        assert bill.cgst_amount == Decimal(exp_cgst), (
            supplier_state,
            f"cgst={bill.cgst_amount}",
        )
        assert bill.sgst_amount == Decimal(exp_sgst), (
            supplier_state,
            f"sgst={bill.sgst_amount}",
        )
        assert bill.igst_amount == Decimal(exp_igst), (
            supplier_state,
            f"igst={bill.igst_amount}",
        )


def test_sync_sales_delivery_posted(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    customer = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Delivery Customer",
        contact_type="CUSTOMER",
        registration_type="CONSUMER",
        is_active=True,
    )
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Delivery Item",
        sku="DL-1",
        hsn_sac="84713010",
        product_type="GOODS",
        uom="PCS",
        sales_price=Decimal("200"),
        purchase_price=Decimal("150"),
        gst_rate=Decimal("18"),
        opening_stock=Decimal("100"),
        current_stock=Decimal("100"),
        reorder_level=Decimal("1"),
        is_active=True,
    )
    sales_order = SalesOrder(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        contact_id=customer.id,
        so_number="SO-100",
        order_date=date(2026, 7, 27),
        due_date=date(2026, 7, 30),
        status="CONFIRMED",
        pos_state_code="27",
    )
    db_session.add_all([customer, product, sales_order])
    db_session.commit()

    delivery_id = uuid.uuid4()
    event = _sync_event(
        tenant,
        "sales_delivery.posted",
        "sales_delivery",
        {
            "sales_order_id": str(sales_order.id),
            "delivery_date": "2026-07-27",
            "customer_name": customer.name,
            "total_cogs_paise": 450000,
            "lines": [
                {
                    "item_id": str(product.id),
                    "product_name": product.name,
                    "quantity": "30",
                    "unit_price_paise": 20000,
                }
            ],
        },
        aggregate_id=delivery_id,
    )

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None
    challan = db_session.query(DeliveryChallan).filter_by(id=delivery_id).one()
    assert challan.status == "ISSUED"
    db_session.refresh(product)
    assert product.current_stock == Decimal("70.0000")
    journal = db_session.query(JournalEntry).filter_by(
        source_type="AUTO",
        source_id=delivery_id,
    ).one()
    lines = db_session.query(JournalLine).filter_by(entry_id=journal.id).all()
    assert sum(line.amount for line in lines if line.direction == "DEBIT") == Decimal("4500.00")


def test_sync_returns_posted(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    customer = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Return Customer",
        contact_type="CUSTOMER",
        registration_type="CONSUMER",
        is_active=True,
    )
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Returned Item",
        sku="RT-1",
        hsn_sac="84713010",
        product_type="GOODS",
        uom="PCS",
        sales_price=Decimal("150"),
        purchase_price=Decimal("100"),
        gst_rate=Decimal("18"),
        opening_stock=Decimal("10"),
        current_stock=Decimal("10"),
        reorder_level=Decimal("1"),
        is_active=True,
    )
    invoice = Invoice(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        contact_id=customer.id,
        invoice_number="INV-RT-1",
        issue_date=date(2026, 7, 27),
        due_date=date(2026, 7, 30),
        status="POSTED",
        subtotal=Decimal("150"),
        cgst_amount=Decimal("13.50"),
        sgst_amount=Decimal("13.50"),
        total=Decimal("177"),
        pos_state_code="27",
    )
    inv_line = InvoiceLine(
        invoice_id=invoice.id,
        product_id=product.id,
        description=product.name,
        quantity=Decimal("1"),
        rate=Decimal("150"),
        subtotal=Decimal("150"),
        hsn_sac="84713010",
        gst_rate=Decimal("18"),
        cgst_amount=Decimal("13.50"),
        sgst_amount=Decimal("13.50"),
        total=Decimal("177"),
    )
    db_session.add_all([customer, product, invoice, inv_line])
    db_session.commit()

    return_id = uuid.uuid4()
    event = _sync_event(
        tenant,
        "sales_return.posted",
        "sales_return",
        {
            "invoice_id": str(invoice.id),
            "party_id": str(customer.id),
            "customer_id": str(customer.id),
            "customer_name": customer.name,
            "return_date": "2026-07-28",
            "total_paise": 17700,
            "lines": [
                {
                    "source_invoice_line_id": str(inv_line.id),
                    "product_name": product.name,
                    "quantity": "1",
                    "unit_price_paise": 15000,
                    "total_paise": 15000,
                }
            ],
        },
        aggregate_id=return_id,
    )

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None
    sales_ret = db_session.query(SalesReturn).filter_by(id=return_id).one()
    assert sales_ret.status == "POSTED"
    db_session.refresh(product)
    assert product.current_stock == Decimal("11.0000")


def test_sync_credit_debit_notes_posted(client, db_session):
    tenant, user, cash, revenue = _seed_sync_tenant(db_session)
    customer = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="CN Customer",
        contact_type="CUSTOMER",
        registration_type="CONSUMER",
        is_active=True,
    )
    invoice = Invoice(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        contact_id=customer.id,
        invoice_number="INV-CN-1",
        issue_date=date(2026, 7, 27),
        due_date=date(2026, 7, 30),
        status="POSTED",
        subtotal=Decimal("500"),
        cgst_amount=Decimal("45.00"),
        sgst_amount=Decimal("45.00"),
        total=Decimal("590"),
        pos_state_code="27",
    )
    db_session.add_all([customer, invoice])
    db_session.commit()

    cn_id = uuid.uuid4()
    event = _sync_event(
        tenant,
        "credit_note.posted",
        "credit_note",
        {
            "number": 1,
            "invoice_id": str(invoice.id),
            "party_id": str(customer.id),
            "customer_id": str(customer.id),
            "customer_name": customer.name,
            "credit_note_date": "2026-07-28",
            "total_paise": 59000,
            "subtotal_paise": 50000,
            "tax_paise": 9000,
        },
        aggregate_id=cn_id,
    )

    response = client.post(
        "/api/v1/apexbooks/sync/push",
        json={"events": [event]},
        headers=_sync_headers(user, tenant),
    )

    assert response.status_code == 200
    assert response.json()["acknowledgements"][0]["error"] is None
    cn = db_session.query(CreditNote).filter_by(id=cn_id).one()
    assert cn.status == "POSTED"

