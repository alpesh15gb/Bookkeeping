from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from datetime import datetime, timezone
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Contact, Product, StockLedger, Account, BankingProfile, ExpenseCategory, TaxTemplate, PaymentTerm
)
from src.schemas.master_schemas import (
    ContactCreate, ContactUpdate, ContactResponse,
    ProductCreate, ProductUpdate, ProductResponse,
    AccountCreate, AccountUpdate, AccountResponse,
    BankingProfileCreate, BankingProfileUpdate, BankingProfileResponse,
    ExpenseCategoryCreate, ExpenseCategoryUpdate, ExpenseCategoryResponse,
    TaxTemplateResponse, PaymentTermResponse
)
from src.api.deps import enforce_permission
from src.domains.accounting.services import LedgerValidationError
from src.domains.inventory.services import resolve_default_warehouse_id, get_warehouse_stock

router = APIRouter(prefix="/masters", tags=["Master Data"])

# ==========================================
# 1. CONTACTS (Customers & Vendors)
# ==========================================

@router.post("/contacts", response_model=ContactResponse, status_code=status.HTTP_201_CREATED)
def create_contact(
    payload: ContactCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("contact:create"))
):
    normalized_name = payload.name.strip().lower()
    normalized_gstin = payload.gstin.strip().upper() if payload.gstin else None

    existing = None
    if normalized_gstin:
        existing = db.query(Contact).filter(
            Contact.tenant_id == tenant_id,
            func.upper(Contact.gstin) == normalized_gstin,
            Contact.deleted_at == None,
        ).first()
    if not existing:
        existing = db.query(Contact).filter(
            Contact.tenant_id == tenant_id,
            func.lower(func.trim(Contact.name)) == normalized_name,
            Contact.deleted_at == None,
        ).first()
    if existing:
        if existing.contact_type != payload.contact_type:
            existing.contact_type = "BOTH"
            db.commit()
            db.refresh(existing)
        return existing

    contact = Contact(
        tenant_id=tenant_id,
        name=payload.name,
        email=payload.email,
        phone=payload.phone,
        contact_type=payload.contact_type,
        gstin=normalized_gstin,
        pan=payload.pan,
        registration_type=payload.registration_type,
        billing_address=(
            payload.billing_address.model_dump()
            if payload.billing_address
            else None
        ),
        shipping_address=payload.shipping_address.model_dump() if payload.shipping_address else None,
        state_code=payload.state_code,
        is_active=True
    )
    db.add(contact)
    db.commit()
    db.refresh(contact)
    return contact

@router.get("/contacts", response_model=List[ContactResponse])
def list_contacts(
    contact_type: Optional[str] = None,
    search: Optional[str] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("contact:view"))
):
    offset = (page - 1) * limit
    q = db.query(Contact).filter(Contact.tenant_id == tenant_id, Contact.deleted_at == None)
    if contact_type:
        if contact_type == "CUSTOMER" or contact_type == "VENDOR":
            q = q.filter(Contact.contact_type.in_([contact_type, "BOTH"]))
        else:
            q = q.filter(Contact.contact_type == contact_type)
    if search:
        q = q.filter(
            Contact.name.ilike(f"%{search}%") |
            Contact.email.ilike(f"%{search}%") |
            Contact.phone.ilike(f"%{search}%") |
            Contact.gstin.ilike(f"%{search}%")
        )
    return q.offset(offset).limit(limit).all()

@router.get("/contacts/{id}", response_model=ContactResponse)
def get_contact(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("contact:view"))
):
    contact = db.query(Contact).filter(
        Contact.id == id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found.")
    return contact

@router.put("/contacts/{id}", response_model=ContactResponse)
def update_contact(
    id: uuid.UUID,
    payload: ContactUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("contact:update"))
):
    contact = db.query(Contact).filter(
        Contact.id == id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found.")

    if payload.name is not None:
        contact.name = payload.name
    if payload.email is not None:
        contact.email = payload.email
    if payload.phone is not None:
        contact.phone = payload.phone
    if payload.contact_type is not None:
        contact.contact_type = payload.contact_type
    if payload.gstin is not None:
        contact.gstin = payload.gstin
    if payload.pan is not None:
        contact.pan = payload.pan
    if payload.registration_type is not None:
        contact.registration_type = payload.registration_type
    if payload.billing_address is not None:
        contact.billing_address = payload.billing_address.dict()
    if payload.shipping_address is not None:
        contact.shipping_address = payload.shipping_address.dict()
    if payload.state_code is not None:
        contact.state_code = payload.state_code
    if payload.is_active is not None:
        contact.is_active = payload.is_active

    db.commit()
    db.refresh(contact)
    return contact

@router.delete("/contacts/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_contact(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("contact:delete"))
):
    contact = db.query(Contact).filter(
        Contact.id == id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found.")

    from src.infrastructure.database.models import Invoice, Bill
    active_invoices = db.query(Invoice).filter(
        Invoice.contact_id == id, Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None, Invoice.status != "CANCELLED"
    ).count()
    active_bills = db.query(Bill).filter(
        Bill.contact_id == id, Bill.tenant_id == tenant_id,
        Bill.deleted_at == None, Bill.status != "CANCELLED"
    ).count()
    if active_invoices > 0 or active_bills > 0:
        raise HTTPException(status_code=400, detail="Cannot delete contact with active invoices or bills. Deactivate instead.")

    contact.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return None


# ==========================================
# 2. PRODUCTS & SERVICES
# ==========================================

@router.post("/products", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
def create_product(
    payload: ProductCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    if payload.product_type == "SERVICE" and payload.opening_stock != 0:
        raise HTTPException(status_code=422, detail="Services cannot have opening stock.")
    normalized_name = payload.name.strip().lower()
    existing = db.query(Product).filter(
        Product.tenant_id == tenant_id,
        func.lower(func.trim(Product.name)) == normalized_name,
        Product.product_type == payload.product_type,
        Product.hsn_sac == payload.hsn_sac,
        Product.deleted_at == None,
    ).first()
    if existing:
        return existing
    if payload.sku:
        existing_sku = db.query(Product.id).filter(
            Product.tenant_id == tenant_id,
            func.lower(Product.sku) == payload.sku.strip().lower(),
            Product.deleted_at == None,
        ).first()
        if existing_sku:
            raise HTTPException(
                status_code=409,
                detail="SKU is already assigned to another product.",
            )
    if payload.barcode:
        duplicate = db.query(Product.id).filter(
            Product.tenant_id == tenant_id,
            Product.barcode == payload.barcode,
            Product.deleted_at == None,
        ).first()
        if duplicate:
            raise HTTPException(status_code=409, detail="Barcode is already assigned to another product.")
    product = Product(
        tenant_id=tenant_id,
        name=payload.name,
        sku=payload.sku,
        barcode=payload.barcode,
        hsn_sac=payload.hsn_sac,
        product_type=payload.product_type,
        uom=payload.uom,
        sales_price=payload.sales_price,
        purchase_price=payload.purchase_price,
        gst_rate=payload.gst_rate,
        opening_stock=payload.opening_stock,
        current_stock=payload.opening_stock,
        reorder_level=payload.reorder_level,
        is_active=True
    )
    db.add(product)
    db.flush()
    if payload.opening_stock > 0 and payload.product_type == "GOODS":
        db.add(StockLedger(
            tenant_id=tenant_id,
            product_id=product.id,
            warehouse_id=resolve_default_warehouse_id(db, tenant_id),
            quantity=payload.opening_stock,
            balance_quantity=payload.opening_stock,
            reference_type="OPENING",
            reference_id=product.id,
            rate=payload.purchase_price,
        ))
    db.commit()
    db.refresh(product)
    return product

@router.get("/products", response_model=List[ProductResponse])
def list_products(
    product_type: Optional[str] = None,
    search: Optional[str] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    q = db.query(Product).filter(Product.tenant_id == tenant_id, Product.deleted_at == None)
    if product_type:
        q = q.filter(Product.product_type == product_type)
    if search:
        q = q.filter(
            Product.name.ilike(f"%{search}%") |
            Product.sku.ilike(f"%{search}%") |
            Product.barcode.ilike(f"%{search}%") |
            Product.hsn_sac.ilike(f"%{search}%")
        )
    return q.offset(offset).limit(limit).all()

@router.get("/products/{id}", response_model=ProductResponse)
def get_product(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    product = db.query(Product).filter(
        Product.id == id,
        Product.tenant_id == tenant_id,
        Product.deleted_at == None
    ).first()
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found.")
    return product

@router.put("/products/{id}", response_model=ProductResponse)
def update_product(
    id: uuid.UUID,
    payload: ProductUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    product = db.query(Product).filter(
        Product.id == id,
        Product.tenant_id == tenant_id,
        Product.deleted_at == None
    ).with_for_update().first()
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found.")

    if payload.name is not None:
        product.name = payload.name
    if payload.sku is not None:
        product.sku = payload.sku
    if "barcode" in payload.model_fields_set:
        if payload.barcode:
            duplicate = db.query(Product.id).filter(
                Product.tenant_id == tenant_id,
                Product.barcode == payload.barcode,
                Product.id != product.id,
                Product.deleted_at == None,
            ).first()
            if duplicate:
                raise HTTPException(status_code=409, detail="Barcode is already assigned to another product.")
        product.barcode = payload.barcode
    if payload.hsn_sac is not None:
        product.hsn_sac = payload.hsn_sac
    if payload.product_type is not None:
        if payload.product_type != product.product_type:
            has_movements = db.query(StockLedger.id).filter(
                StockLedger.tenant_id == tenant_id,
                StockLedger.product_id == product.id,
            ).first()
            if has_movements:
                raise HTTPException(
                    status_code=409,
                    detail="Product type cannot be changed after stock movements exist.",
                )
            if payload.product_type == "SERVICE" and (product.current_stock or 0) != 0:
                raise HTTPException(status_code=409, detail="Reduce stock to zero before converting this item to a service.")
        product.product_type = payload.product_type
    if payload.uom is not None:
        product.uom = payload.uom
    if payload.sales_price is not None:
        product.sales_price = payload.sales_price
    if payload.purchase_price is not None:
        product.purchase_price = payload.purchase_price
    if payload.gst_rate is not None:
        product.gst_rate = payload.gst_rate
    if payload.opening_stock is not None:
        delta = payload.opening_stock - (product.opening_stock or Decimal("0"))
        new_balance = (product.current_stock or Decimal("0")) + delta
        warehouse_id = resolve_default_warehouse_id(db, tenant_id)
        location_stock = get_warehouse_stock(
            db, tenant_id, warehouse_id, product.id
        )
        location_after = (location_stock + delta) if location_stock is not None else new_balance
        if new_balance < 0 or location_after < 0:
            raise HTTPException(
                status_code=409,
                detail="Opening stock cannot be reduced below stock already issued or transferred from the default warehouse.",
            )
        product.opening_stock = payload.opening_stock
        if delta != 0 and product.product_type == "GOODS":
            product.current_stock = new_balance
            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=product.id,
                warehouse_id=warehouse_id,
                quantity=delta,
                balance_quantity=new_balance,
                reference_type="OPENING",
                reference_id=product.id,
                rate=product.purchase_price,
            ))
    if payload.reorder_level is not None:
        product.reorder_level = payload.reorder_level
    if payload.is_active is not None:
        product.is_active = payload.is_active

    db.commit()
    db.refresh(product)
    return product

@router.delete("/products/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    product = db.query(Product).filter(
        Product.id == id,
        Product.tenant_id == tenant_id,
        Product.deleted_at == None
    ).first()
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Product not found.")

    from src.infrastructure.database.models import (
        InvoiceLine, BillLine, SalesOrderLine, DeliveryChallanLine,
        Invoice, Bill, SalesOrder, DeliveryChallan
    )
    active_inv_lines = db.query(InvoiceLine).join(InvoiceLine.invoice).filter(
        InvoiceLine.product_id == id,
        Invoice.deleted_at == None,
        Invoice.status != "CANCELLED"
    ).count()
    active_bill_lines = db.query(BillLine).join(BillLine.bill).filter(
        BillLine.product_id == id,
        Bill.deleted_at == None,
        Bill.status != "CANCELLED"
    ).count()
    active_so_lines = db.query(SalesOrderLine).join(SalesOrderLine.sales_order).filter(
        SalesOrderLine.product_id == id,
        SalesOrder.deleted_at == None,
        SalesOrder.status != "CANCELLED"
    ).count()
    active_dc_lines = db.query(DeliveryChallanLine).join(DeliveryChallanLine.delivery_challan).filter(
        DeliveryChallanLine.product_id == id,
        DeliveryChallan.deleted_at == None,
        DeliveryChallan.status != "CANCELLED"
    ).count()
    if active_inv_lines > 0 or active_bill_lines > 0 or active_so_lines > 0 or active_dc_lines > 0:
        raise HTTPException(status_code=400, detail="Cannot delete product with active invoice, bill, sales order, or delivery challan lines.")

    try:
        product.deleted_at = datetime.now(timezone.utc)
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete product: {str(e)}")
    return None


# ==========================================
# 3. CHART OF ACCOUNTS (Accounts)
# ==========================================

@router.post("/accounts", response_model=AccountResponse, status_code=status.HTTP_201_CREATED)
def create_account(
    payload: AccountCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage"))
):
    # Verify parent exists if supplied
    if payload.parent_id:
        parent = db.query(Account).filter(Account.id == payload.parent_id, Account.tenant_id == tenant_id, Account.deleted_at == None).first()
        if not parent:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Parent account not found.")
        if not parent.is_active:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Parent account is inactive.")
        if parent.account_type != payload.account_type:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Parent and child accounts must have the same account type.",
            )

    # Check for duplicate code
    dup = db.query(Account).filter(Account.tenant_id == tenant_id, Account.code == payload.code, Account.deleted_at == None).first()
    if dup:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Account with code {payload.code} already exists.")

    account = Account(
        tenant_id=tenant_id,
        name=payload.name,
        code=payload.code,
        account_type=payload.account_type,
        account_group=payload.account_group,
        parent_id=payload.parent_id,
        opening_balance=payload.opening_balance,
        current_balance=payload.opening_balance,
        is_active=True
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account

@router.get("/accounts", response_model=List[AccountResponse])
def list_accounts(
    page: int = 1,
    limit: int = 100,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    offset = (page - 1) * limit
    return db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.deleted_at == None
    ).order_by(Account.code.asc()).offset(offset).limit(limit).all()


@router.post("/accounts/seed-defaults")
def seed_default_accounts(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage"))
):
    """Bulk-create all standard chart of accounts for this tenant."""
    from src.domains.accounting.services import AccountResolver, _STANDARD_ACCOUNTS
    
    resolver = AccountResolver(db, tenant_id)
    created = 0
    skipped = 0
    
    for key in _STANDARD_ACCOUNTS:
        try:
            resolver.resolve(key)
            created += 1
        except LedgerValidationError:
            skipped += 1
        except Exception as exc:
            import logging
            logging.getLogger(__name__).warning("Failed to seed account %s: %s", key, exc)
            skipped += 1
    
    db.commit()
    return {
        "created": created,
        "skipped": skipped,
        "total": len(_STANDARD_ACCOUNTS),
        "message": f"Seeded {created} standard accounts ({skipped} already existed)."
    }


@router.post("/accounts/dedupe-contact-accounts")
def dedupe_contact_accounts(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage"))
):
    """Merge duplicate auto-created AR/AP accounts for the same contact name."""
    from src.infrastructure.database.models import JournalLine
    from src.domains.accounting.services import update_account_balances

    accounts = db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.deleted_at == None,
        (Account.code.like("AR-%") | Account.code.like("AP-%")),
    ).order_by(Account.created_at.asc()).all()

    grouped = {}
    for account in accounts:
        key = (account.account_type, account.name.strip().lower())
        grouped.setdefault(key, []).append(account)

    merged = 0
    affected = set()
    now = datetime.now(timezone.utc)

    for group in grouped.values():
        if len(group) < 2:
            continue

        group.sort(
            key=lambda a: (
                0 if abs(a.current_balance or 0) > 0 else 1,
                a.created_at or now,
            )
        )
        primary = group[0]
        affected.add(primary.id)

        for duplicate in group[1:]:
            db.query(JournalLine).filter(
                JournalLine.account_id == duplicate.id,
            ).update({JournalLine.account_id: primary.id}, synchronize_session=False)

            primary.opening_balance = (primary.opening_balance or 0) + (duplicate.opening_balance or 0)
            duplicate.opening_balance = 0
            duplicate.current_balance = 0
            duplicate.is_active = False
            duplicate.deleted_at = now
            merged += 1

    if affected:
        update_account_balances(db, tenant_id, affected)
    db.commit()
    return {"merged_accounts": merged}


@router.get("/accounts/{id}", response_model=AccountResponse)
def get_account(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    account = db.query(Account).filter(Account.id == id, Account.tenant_id == tenant_id, Account.deleted_at == None).first()
    if not account:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")
    return account

@router.put("/accounts/{id}", response_model=AccountResponse)
def update_account(
    id: uuid.UUID,
    payload: AccountUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage"))
):
    account = db.query(Account).filter(Account.id == id, Account.tenant_id == tenant_id, Account.deleted_at == None).first()
    if not account:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")

    if payload.parent_id is not None:
        if payload.parent_id == id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="An account cannot be its own parent.")
        parent = db.query(Account).filter(Account.id == payload.parent_id, Account.tenant_id == tenant_id, Account.deleted_at == None).first()
        if not parent:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Parent account not found.")
        if not parent.is_active:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Parent account is inactive.")
        if parent.account_type != account.account_type:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Parent and child accounts must have the same account type.",
            )

        # Walk upward from the proposed parent. A self-check alone does not
        # prevent A -> B -> A cycles, which break COA traversal and reporting.
        ancestor = parent
        visited = set()
        while ancestor is not None:
            if ancestor.id == account.id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Account hierarchy cannot contain a cycle.",
                )
            if ancestor.id in visited:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Existing account hierarchy contains a cycle.",
                )
            visited.add(ancestor.id)
            if ancestor.parent_id is None:
                break
            ancestor = db.query(Account).filter(
                Account.id == ancestor.parent_id,
                Account.tenant_id == tenant_id,
                Account.deleted_at == None,
            ).first()
        account.parent_id = payload.parent_id

    if payload.name is not None:
        account.name = payload.name
    if payload.code is not None:
        dup = db.query(Account).filter(
            Account.tenant_id == tenant_id, Account.code == payload.code, Account.id != id, Account.deleted_at == None
        ).first()
        if dup:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Account with code {payload.code} already exists.")
        account.code = payload.code
    if payload.opening_balance is not None:
        # adjust current balance by the difference in opening balance
        diff = payload.opening_balance - account.opening_balance
        account.opening_balance = payload.opening_balance
        account.current_balance += diff
    if payload.is_active is not None:
        account.is_active = payload.is_active

    db.commit()
    db.refresh(account)
    return account


@router.delete("/accounts/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage"))
):
    account = db.query(Account).filter(
        Account.id == id,
        Account.tenant_id == tenant_id,
        Account.deleted_at == None
    ).first()
    if not account:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")

    from src.infrastructure.database.models import JournalLine

    child_count = db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.parent_id == account.id,
        Account.deleted_at == None,
    ).count()
    if child_count:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete an account with child accounts. Reassign or deactivate the children first.",
        )

    has_journal_activity = db.query(JournalLine.id).filter(
        JournalLine.account_id == account.id,
    ).first() is not None
    has_balance = account.opening_balance != 0 or account.current_balance != 0
    if has_journal_activity or has_balance:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete an account with balances or posted journal activity. Deactivate it instead.",
        )
    account.deleted_at = datetime.now(timezone.utc)
    db.commit()


# ==========================================
# 4. BANKING PROFILES
# ==========================================

@router.post("/banking-profiles", response_model=BankingProfileResponse, status_code=status.HTTP_201_CREATED)
def create_banking_profile(
    payload: BankingProfileCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    if payload.is_primary:
        # Clear primary flag on all other profiles
        db.query(BankingProfile).filter(BankingProfile.tenant_id == tenant_id).update({"is_primary": False})

    profile = BankingProfile(
        tenant_id=tenant_id,
        bank_name=payload.bank_name,
        account_number=payload.account_number,
        ifsc_code=payload.ifsc_code,
        branch_name=payload.branch_name,
        account_holder_name=payload.account_holder_name,
        upi_id=payload.upi_id,
        is_primary=payload.is_primary,
        is_active=True
    )
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile

@router.get("/banking-profiles", response_model=List[BankingProfileResponse])
def list_banking_profiles(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:view"))
):
    return db.query(BankingProfile).filter(
        BankingProfile.tenant_id == tenant_id
    ).all()

@router.get("/banking-profiles/{id}", response_model=BankingProfileResponse)
def get_banking_profile(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:view"))
):
    profile = db.query(BankingProfile).filter(
        BankingProfile.id == id,
        BankingProfile.tenant_id == tenant_id
    ).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Banking profile not found.")
    return profile

@router.put("/banking-profiles/{id}", response_model=BankingProfileResponse)
def update_banking_profile(
    id: uuid.UUID,
    payload: BankingProfileUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    profile = db.query(BankingProfile).filter(
        BankingProfile.id == id,
        BankingProfile.tenant_id == tenant_id
    ).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Banking profile not found.")

    if payload.is_primary:
        # Clear primary flag on all other profiles
        db.query(BankingProfile).filter(BankingProfile.tenant_id == tenant_id).update({"is_primary": False})
        profile.is_primary = True

    if payload.bank_name is not None:
        profile.bank_name = payload.bank_name
    if payload.account_number is not None:
        profile.account_number = payload.account_number
    if payload.ifsc_code is not None:
        profile.ifsc_code = payload.ifsc_code
    if payload.branch_name is not None:
        profile.branch_name = payload.branch_name
    if payload.account_holder_name is not None:
        profile.account_holder_name = payload.account_holder_name
    if payload.upi_id is not None:
        profile.upi_id = payload.upi_id
    if payload.is_primary is False:
        profile.is_primary = False
    if payload.is_active is not None:
        profile.is_active = payload.is_active

    db.commit()
    db.refresh(profile)
    return profile

@router.delete("/banking-profiles/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_banking_profile(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    profile = db.query(BankingProfile).filter(
        BankingProfile.id == id,
        BankingProfile.tenant_id == tenant_id
    ).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Banking profile not found.")

    db.delete(profile)
    db.commit()
    return None


# ==========================================
# 5. EXPENSE CATEGORIES
# ==========================================

@router.post("/expense-categories", response_model=ExpenseCategoryResponse, status_code=status.HTTP_201_CREATED)
def create_expense_category(
    payload: ExpenseCategoryCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:manual_post"))
):
    linked_account_id = payload.linked_account_id
    if not linked_account_id:
        from src.domains.accounting.services import AccountResolver
        resolver = AccountResolver(db, tenant_id)
        linked_account_id = resolver.resolve("purchases")

    acc = db.query(Account).filter(
        Account.id == linked_account_id,
        Account.tenant_id == tenant_id,
        Account.deleted_at == None
    ).first()
    if not acc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Linked ledger account not found.")

    cat = ExpenseCategory(
        tenant_id=tenant_id,
        name=payload.name,
        description=payload.description,
        linked_account_id=linked_account_id,
        is_active=True
    )
    db.add(cat)
    db.commit()
    db.refresh(cat)
    return cat

@router.get("/expense-categories", response_model=List[ExpenseCategoryResponse])
def list_expense_categories(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    return db.query(ExpenseCategory).filter(
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.is_active == True
    ).all()

@router.get("/expense-categories/{id}", response_model=ExpenseCategoryResponse)
def get_expense_category(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    cat = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == id,
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.is_active == True
    ).first()
    if not cat:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense category not found.")
    return cat

@router.put("/expense-categories/{id}", response_model=ExpenseCategoryResponse)
def update_expense_category(
    id: uuid.UUID,
    payload: ExpenseCategoryUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:manual_post"))
):
    cat = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == id,
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.is_active == True
    ).first()
    if not cat:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense category not found.")

    if payload.linked_account_id is not None:
        if payload.linked_account_id:
            acc = db.query(Account).filter(Account.id == payload.linked_account_id, Account.tenant_id == tenant_id, Account.deleted_at == None).first()
            if not acc:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Linked ledger account not found.")
        cat.linked_account_id = payload.linked_account_id

    if payload.name is not None:
        cat.name = payload.name
    if payload.description is not None:
        cat.description = payload.description
    if payload.is_active is not None:
        cat.is_active = payload.is_active

    db.commit()
    db.refresh(cat)
    return cat

@router.delete("/expense-categories/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense_category(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:manual_post"))
):
    cat = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == id,
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.is_active == True
    ).first()
    if not cat:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense category not found.")

    db.delete(cat)
    db.commit()
    return None


# ==========================================
# 6. TAX TEMPLATES & PAYMENT TERMS
# ==========================================

@router.get("/tax-templates", response_model=List[TaxTemplateResponse])
def list_tax_templates(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    # Returns global standard rates (where tenant_id is Null) AND tenant specific rates
    return db.query(TaxTemplate).filter(
        TaxTemplate.is_active == True,
        (TaxTemplate.tenant_id == None) | (TaxTemplate.tenant_id == tenant_id)
    ).all()

@router.get("/payment-terms", response_model=List[PaymentTermResponse])
def list_payment_terms(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    return db.query(PaymentTerm).filter(
        PaymentTerm.is_active == True,
        (PaymentTerm.tenant_id == None) | (PaymentTerm.tenant_id == tenant_id)
    ).all()
