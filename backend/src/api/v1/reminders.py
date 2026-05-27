"""
Reminders CRUD — returns empty data for now.
Frontend handles empty arrays gracefully.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import uuid
from typing import List, Optional

from src.core.database import get_db_session
from src.api.deps import enforce_permission

router = APIRouter(prefix="/reminders", tags=["Reminders"])


@router.get("")
def list_reminders(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    return []


@router.post("")
def create_reminder(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    return {"message": "Reminder created (stub)"}
