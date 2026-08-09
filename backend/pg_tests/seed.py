"""ORM-based seeding for the PostgreSQL integration suite.

Uses the real SQLAlchemy models so the test database mirrors production
schema exactly.  All seeding runs through the admin (superuser) session which
bypasses RLS.
"""

import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy.orm import Session

from src.infrastructure.database.models import (
    Account,
    AuditLog,
    Bill,
    BillLine,
    BillPayment,
    BillPaymentAllocation,
    Branch,
    Contact,
    Invoice,
    InvoiceLine,
    JournalEntry,
    JournalLine,
    Payment,
    PaymentAllocation,
    Product,
    StockLedger,
    Tenant,
    TenantMembership,
    User,
)

TENANT_A = uuid.UUID("aaaaaaaa-0000-0000-0000-000000000001")
TENANT_B = uuid.UUID("aaaaaaaa-0000-0000-0000-000000000002")


def seed_tenants(db: Session):
    """Idempotent: tenants use fixed ids, so skip any that already exist."""
    existing = {
        row[0] for row in db.query(Tenant.id).filter(Tenant.id.in_([TENANT_A, TENANT_B])).all()
    }
    if TENANT_A not in existing:
        db.add(Tenant(
            id=TENANT_A,
            legal_name="Tenant A Ltd",
            financial_year_start=date(2026, 4, 1),
        ))
    if TENANT_B not in existing:
        db.add(Tenant(
            id=TENANT_B,
            legal_name="Tenant B Pvt",
            financial_year_start=date(2026, 4, 1),
        ))
    db.flush()


def seed_user(db: Session, tenant_id: uuid.UUID) -> User:
    user = User(
        id=uuid.uuid4(),
        email=f"owner-{tenant_id.hex[:8]}@test.local",
        full_name="Owner",
        hashed_password="x",
        is_active=True,
    )
    db.add(user)
    db.flush()
    db.add(TenantMembership(
        tenant_id=tenant_id,
        user_id=user.id,
        role="owner",
        is_active=True,
    ))
    db.flush()
    return user


def seed_warehouse(db: Session, tenant_id: uuid.UUID, name: str) -> Branch:
    warehouse = Branch(
        tenant_id=tenant_id,
        name=name,
        address={"street": "1 Main St", "city": "Bengaluru", "state_code": "27", "pincode": "560001", "country": "India"},
        is_active=True,
    )
    db.add(warehouse)
    db.flush()
    return warehouse


def seed_contact(db: Session, tenant_id: uuid.UUID, name: str) -> Contact:
    contact = Contact(
        tenant_id=tenant_id,
        name=name,
        contact_type="CUSTOMER",
        registration_type="REGULAR",
        email=f"{name}@test.local",
        is_active=True,
    )
    db.add(contact)
    db.flush()
    return contact


def seed_product(db: Session, tenant_id: uuid.UUID, name: str, current_stock: Decimal = Decimal("0")) -> Product:
    product = Product(
        tenant_id=tenant_id,
        name=name,
        sku=f"SKU-{name}",
        hsn_sac="9983",
        product_type="GOODS",
        uom="PCS",
        sales_price=Decimal("100.00"),
        purchase_price=Decimal("60.00"),
        gst_rate=Decimal("18.00"),
        current_stock=current_stock,
    )
    db.add(product)
    db.flush()
    return product


def seed_invoice(
    db: Session,
    tenant_id: uuid.UUID,
    contact: Contact,
    number: str,
    total: Decimal = Decimal("118.00"),
) -> Invoice:
    invoice = Invoice(
        tenant_id=tenant_id,
        contact_id=contact.id,
        invoice_number=number,
        issue_date=date.today(),
        due_date=date.today(),
        status="POSTED",
        subtotal=Decimal("100.00"),
        cgst_amount=Decimal("9.00"),
        sgst_amount=Decimal("9.00"),
        igst_amount=Decimal("0.00"),
        utgst_amount=Decimal("0.00"),
        cess_amount=Decimal("0.00"),
        round_off=Decimal("0.00"),
        shipping_charges=Decimal("0.00"),
        total=total,
        amount_paid=Decimal("0.00"),
        e_invoice_status="PENDING",
        pos_state_code="27",
        currency="INR",
        exchange_rate=Decimal("1.000000"),
    )
    db.add(invoice)
    db.flush()
    db.add(InvoiceLine(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        description=f"line for {number}",
        quantity=Decimal("1.0000"),
        rate=Decimal("100.0000"),
        discount=Decimal("0.0000"),
        subtotal=Decimal("100.0000"),
        hsn_sac="9983",
        gst_rate=Decimal("18.00"),
        cgst_rate=Decimal("9.00"),
        cgst_amount=Decimal("9.0000"),
        sgst_rate=Decimal("9.00"),
        sgst_amount=Decimal("9.0000"),
        igst_rate=Decimal("0.00"),
        igst_amount=Decimal("0.0000"),
        utgst_rate=Decimal("0.00"),
        utgst_amount=Decimal("0.0000"),
        cess_rate=Decimal("0.00"),
        cess_amount=Decimal("0.0000"),
        total=Decimal("118.0000"),
    ))
    db.flush()
    return invoice


def seed_bill(
    db: Session,
    tenant_id: uuid.UUID,
    vendor: Contact,
    number: str,
    total: Decimal = Decimal("118.00"),
) -> Bill:
    bill = Bill(
        tenant_id=tenant_id,
        contact_id=vendor.id,
        bill_number=number,
        issue_date=date.today(),
        due_date=date.today(),
        status="POSTED",
        subtotal=Decimal("100.00"),
        cgst_amount=Decimal("9.00"),
        sgst_amount=Decimal("9.00"),
        igst_amount=Decimal("0.00"),
        utgst_amount=Decimal("0.00"),
        cess_amount=Decimal("0.00"),
        round_off=Decimal("0.00"),
        shipping_charges=Decimal("0.00"),
        total=total,
        amount_paid=Decimal("0.00"),
        pos_state_code="27",
    )
    db.add(bill)
    db.flush()
    db.add(BillLine(
        tenant_id=tenant_id,
        bill_id=bill.id,
        description=f"bill line for {number}",
        quantity=Decimal("1.0000"),
        rate=Decimal("100.0000"),
        discount=Decimal("0.0000"),
        subtotal=Decimal("100.0000"),
        hsn_sac="9983",
        gst_rate=Decimal("18.00"),
        cgst_rate=Decimal("9.00"),
        cgst_amount=Decimal("9.0000"),
        sgst_rate=Decimal("9.00"),
        sgst_amount=Decimal("9.0000"),
        igst_rate=Decimal("0.00"),
        igst_amount=Decimal("0.0000"),
        utgst_rate=Decimal("0.00"),
        utgst_amount=Decimal("0.0000"),
        cess_rate=Decimal("0.00"),
        cess_amount=Decimal("0.0000"),
        total=Decimal("118.0000"),
    ))
    db.flush()
    return bill


def seed_payment(
    db: Session,
    tenant_id: uuid.UUID,
    contact: Contact,
    number: str,
    amount: Decimal = Decimal("118.00"),
) -> Payment:
    payment = Payment(
        tenant_id=tenant_id,
        contact_id=contact.id,
        payment_number=number,
        payment_date=date.today(),
        payment_mode="BANK",
        amount=amount,
        status="ACTIVE",
    )
    db.add(payment)
    db.flush()
    return payment


def seed_bill_payment(
    db: Session,
    tenant_id: uuid.UUID,
    contact: Contact,
    number: str,
    amount: Decimal = Decimal("118.00"),
) -> BillPayment:
    bill_payment = BillPayment(
        tenant_id=tenant_id,
        contact_id=contact.id,
        payment_number=number,
        payment_date=date.today(),
        payment_mode="BANK",
        amount=amount,
        status="ACTIVE",
    )
    db.add(bill_payment)
    db.flush()
    return bill_payment


def seed_payment_allocation(
    db: Session,
    tenant_id: uuid.UUID,
    payment: Payment,
    invoice: Invoice,
    amount: Decimal = Decimal("118.00"),
) -> PaymentAllocation:
    allocation = PaymentAllocation(
        tenant_id=tenant_id,
        payment_id=payment.id,
        invoice_id=invoice.id,
        amount=amount,
    )
    db.add(allocation)
    db.flush()
    return allocation


def seed_bill_payment_allocation(
    db: Session,
    tenant_id: uuid.UUID,
    payment: BillPayment,
    bill: Bill,
    amount: Decimal = Decimal("118.00"),
) -> BillPaymentAllocation:
    allocation = BillPaymentAllocation(
        tenant_id=tenant_id,
        payment_id=payment.id,
        bill_id=bill.id,
        amount=amount,
    )
    db.add(allocation)
    db.flush()
    return allocation


def seed_journal_entry(
    db: Session,
    tenant_id: uuid.UUID,
    account_debit: Account,
    account_credit: Account,
    source_type: str,
    source_id: uuid.UUID,
    amount: Decimal = Decimal("100.00"),
) -> JournalEntry:
    entry = JournalEntry(
        tenant_id=tenant_id,
        entry_date=date.today(),
        reference_number=f"JR-{uuid.uuid4().hex[:8]}",
        source_type=source_type,
        source_id=source_id,
        description="test entry",
    )
    db.add(entry)
    db.flush()
    db.add(JournalLine(
        tenant_id=tenant_id,
        entry_id=entry.id,
        account_id=account_debit.id,
        amount=amount,
        direction="DEBIT",
        narration="debit leg",
    ))
    db.add(JournalLine(
        tenant_id=tenant_id,
        entry_id=entry.id,
        account_id=account_credit.id,
        amount=amount,
        direction="CREDIT",
        narration="credit leg",
    ))
    db.flush()
    return entry


def seed_account(db: Session, tenant_id: uuid.UUID, name: str, code: str, account_type: str) -> Account:
    account = Account(
        tenant_id=tenant_id,
        name=name,
        code=code,
        account_type=account_type,
        is_active=True,
    )
    db.add(account)
    db.flush()
    return account


def seed_stock_ledger(
    db: Session,
    tenant_id: uuid.UUID,
    product: Product,
    warehouse_id: uuid.UUID,
    quantity: Decimal,
    balance: Decimal,
) -> StockLedger:
    move = StockLedger(
        tenant_id=tenant_id,
        product_id=product.id,
        warehouse_id=warehouse_id,
        reference_type="INVENTORY_ADJUSTMENT",
        reference_id=uuid.uuid4(),
        quantity=quantity,
        balance_quantity=balance,
        rate=Decimal("0.00"),
    )
    db.add(move)
    db.flush()
    return move


def seed_audit_log(db: Session, tenant_id: uuid.UUID) -> AuditLog:
    entry = AuditLog(
        tenant_id=tenant_id,
        actor_id=uuid.uuid4(),
        actor_email="audit@test.local",
        action="test.created",
        entity_type="Invoice",
        entity_id=uuid.uuid4(),
        after_state={"x": 1},
        timestamp=date.today(),
    )
    db.add(entry)
    db.flush()
    return entry
