import re
from pydantic import BaseModel, Field, EmailStr, field_validator
from typing import Optional
import uuid
from datetime import datetime
from src.schemas import SchemaBase

class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    full_name: str = Field(..., max_length=150)
    phone_number: Optional[str] = Field(None, max_length=15)
    company_legal_name: str = Field(..., max_length=150)
    company_gstin: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    company_pan: Optional[str] = Field(None, pattern="^[A-Z]{5}[0-9]{4}[A-Z]{1}$")

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        if not re.search(r"[A-Z]", v):
            raise ValueError("Password must contain at least one uppercase letter.")
        if not re.search(r"[a-z]", v):
            raise ValueError("Password must contain at least one lowercase letter.")
        if not re.search(r"\d", v):
            raise ValueError("Password must contain at least one digit.")
        if not re.search(r"[!@#$%^&*(),.?\":{}|<>\-_=+\[\]\\/]", v):
            raise ValueError("Password must contain at least one special character.")
        return v

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = 900

class UserResponse(SchemaBase):
    id: uuid.UUID
    email: EmailStr
    full_name: str
    phone_number: Optional[str]
    is_active: bool
    email_verified: bool = False
    totp_enabled: bool = False
    created_at: datetime

class TenantResponse(SchemaBase):
    id: uuid.UUID
    legal_name: str
    trade_name: Optional[str]
    gstin: Optional[str]
    pan: Optional[str]
