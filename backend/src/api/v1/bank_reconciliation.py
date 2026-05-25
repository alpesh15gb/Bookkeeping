from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    BankStatement, BankTransaction, BankReconciliation, BankingProfile,
    Payment, BillPayment, JournalEntry, JournalLine
)
from src.schemas.bill_schemas import (
    BankStatementCreate, BankStatementResponse, BankStatementListResponse,
    BankTransactionCreate, BankTransactionResponse,
    BankReconciliationCreate, BankReconciliationResponse, BankReconciliationListResponse
)
from src.domains.accounting.services import AccountResolver
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/bank-reconciliation", tags=["Bank Reconciliation"])


# BANK STATEMENT ENDPOINTS
@router.post("/statements", response_model=BankStatementResponse, status_code=status.HTTP_201_CREATED)
def create_bank_statement(
    payload: BankStatementCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    # Verify banking profile belongs to tenant
    banking_profile = db.query(BankingProfile).filter(
        BankingProfile.id == payload.banking_profile_id,
        BankingProfile.tenant_id == tenant_id
    ).first()
    if not banking_profile:
        raise HTTPException(status_code=404, detail="Banking profile not found.")

    statement = BankStatement(
        tenant_id=tenant_id,
        banking_profile_id=payload.banking_profile_id,
        statement_date=payload.statement_date,
        starting_balance=payload.starting_balance,
        ending_balance=payload.ending_balance,
        currency=payload.currency,
        status="IMPORTED"
    )

    db.add(statement)
    db.commit()
    db.refresh(statement)
    return statement


@router.get("/statements", response_model=List[BankStatementListResponse])
def list_bank_statements(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(BankStatement).filter(
        BankStatement.tenant_id == tenant_id
    ).offset(offset).limit(limit).all()

    response = []
    for stmt in results:
        response.append(BankStatementListResponse(
            id=stmt.id,
            statement_date=stmt.statement_date,
            status=stmt.status,
            created_at=stmt.created_at
        ))
    return response


@router.get("/statements/{id}", response_model=BankStatementResponse)
def get_bank_statement(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    statement = db.query(BankStatement).filter(
        BankStatement.id == id,
        BankStatement.tenant_id == tenant_id
    ).first()
    if not statement:
        raise HTTPException(status_code=404, detail="Bank statement not found.")
    return statement


# BANK TRANSACTION ENDPOINTS
@router.post("/statements/{statement_id}/transactions", response_model=BankTransactionResponse, status_code=status.HTTP_201_CREATED)
def create_bank_transaction(
    statement_id: uuid.UUID,
    payload: BankTransactionCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    # Verify bank statement belongs to tenant
    statement = db.query(BankStatement).filter(
        BankStatement.id == statement_id,
        BankStatement.tenant_id == tenant_id
    ).first()
    if not statement:
        raise HTTPException(status_code=404, detail="Bank statement not found.")

    transaction = BankTransaction(
        bank_statement_id=statement_id,
        transaction_date=payload.transaction_date,
        amount=payload.amount,
        description=payload.description,
        reference_number=payload.reference_number,
        status="PENDING"
    )

    db.add(transaction)
    db.commit()
    db.refresh(transaction)
    return transaction


@router.get("/statements/{statement_id}/transactions", response_model=List[BankTransactionResponse])
def list_bank_transactions(
    statement_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    # Verify bank statement belongs to tenant
    statement = db.query(BankStatement).filter(
        BankStatement.id == statement_id,
        BankStatement.tenant_id == tenant_id
    ).first()
    if not statement:
        raise HTTPException(status_code=404, detail="Bank statement not found.")

    transactions = db.query(BankTransaction).filter(
        BankTransaction.bank_statement_id == statement_id
    ).all()

    response = []
    for txn in transactions:
        response.append(BankTransactionResponse(
            id=txn.id,
            transaction_date=txn.transaction_date,
            amount=txn.amount,
            description=txn.description,
            reference_number=txn.reference_number,
            status=txn.status,
            created_at=txn.created_at,
            updated_at=txn.updated_at
        ))
    return response


# BANK RECONCILIATION ENDPOINTS
@router.post("/transactions/{transaction_id}/reconcile", response_model=BankReconciliationResponse, status_code=status.HTTP_201_CREATED)
def reconcile_bank_transaction(
    transaction_id: uuid.UUID,
    payload: BankReconciliationCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    # Verify bank transaction belongs to tenant via statement
    transaction = db.query(BankTransaction).join(BankStatement).filter(
        BankTransaction.id == transaction_id,
        BankStatement.tenant_id == tenant_id
    ).first()
    if not transaction:
        raise HTTPException(status_code=404, detail="Bank transaction not found.")

    if transaction.status != "PENDING":
        raise HTTPException(status_code=400, detail="Only pending transactions can be reconciled.")

    # Verify that either payment_id or bill_payment_id is provided (but not both)
    if payload.payment_id is not None and payload.bill_payment_id is not None:
        raise HTTPException(status_code=400, detail="Cannot reconcile with both payment and bill payment.")
    
    if payload.payment_id is None and payload.bill_payment_id is None:
        raise HTTPException(status_code=400, detail="Must specify either payment_id or bill_payment_id.")

    # Verify payment belongs to tenant if provided
    if payload.payment_id:
        payment = db.query(Payment).filter(
            Payment.id == payload.payment_id,
            Payment.tenant_id == tenant_id
        ).first()
        if not payment:
            raise HTTPException(status_code=404, detail="Payment not found.")

    # Verify bill payment belongs to tenant if provided
    if payload.bill_payment_id:
        bill_payment = db.query(BillPayment).filter(
            BillPayment.id == payload.bill_payment_id,
            BillPayment.tenant_id == tenant_id
        ).first()
        if not bill_payment:
            raise HTTPException(status_code=404, detail="Bill payment not found.")

    # Check if already reconciled
    existing_reconciliation = db.query(BankReconciliation).filter(
        BankReconciliation.bank_transaction_id == transaction_id
    ).first()
    if existing_reconciliation:
        raise HTTPException(status_code=400, detail="Transaction already reconciled.")

    reconciliation = BankReconciliation(
        bank_transaction_id=transaction_id,
        payment_id=payload.payment_id,
        bill_payment_id=payload.bill_payment_id,
        amount=payload.amount,
        notes=payload.notes
    )

    # Update transaction status
    transaction.status = "RECONCILED"

    db.add(reconciliation)
    db.commit()
    db.refresh(reconciliation)
    return reconciliation


@router.get("/reconciliations", response_model=List[BankReconciliationListResponse])
def list_bank_reconciliations(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    # Join with bank statement to filter by tenant
    offset = (page - 1) * limit
    results = db.query(BankReconciliation).join(BankTransaction).join(BankStatement).filter(
        BankStatement.tenant_id == tenant_id
    ).offset(offset).limit(limit).all()

    response = []
    for recon in results:
        response.append(BankReconciliationListResponse(
            id=recon.id,
            bank_transaction_id=recon.bank_transaction_id,
            amount=recon.amount,
            notes=recon.notes,
            created_at=recon.created_at
        ))
    return response


@router.get("/reconciliations/{id}", response_model=BankReconciliationResponse)
def get_bank_reconciliation(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    reconciliation = db.query(BankReconciliation).join(BankTransaction).join(BankStatement).filter(
        BankReconciliation.id == id,
        BankStatement.tenant_id == tenant_id
    ).first()
    if not reconciliation:
        raise HTTPException(status_code=404, detail="Bank reconciliation not found.")
    return reconciliation


@router.post("/reconciliations/{id}/undo", response_model=BankReconciliationResponse)
def undo_bank_reconciliation(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    reconciliation = db.query(BankReconciliation).join(BankTransaction).join(BankStatement).filter(
        BankReconciliation.id == id,
        BankStatement.tenant_id == tenant_id
    ).first()
    if not reconciliation:
        raise HTTPException(status_code=404, detail="Bank reconciliation not found.")

    # Update transaction status back to pending
    transaction = db.query(BankTransaction).filter(
        BankTransaction.id == reconciliation.bank_transaction_id
    ).first()
    if transaction:
        transaction.status = "PENDING"

    db.delete(reconciliation)
    db.commit()
    
    # Return the reconciliation object before deletion (for API consistency)
    return reconciliation