import pytest
from unittest.mock import Mock, patch
from uuid import UUID, uuid4
from datetime import datetime, timedelta, timezone
from typing import List

from src.core.security import create_access_token, decode_token, SECRET_KEY, ALGORITHM
import jwt


class TestAuthService:
    """Test authentication service logic."""

    def test_create_access_token(self):
        """Test JWT token creation."""
        user_id = uuid4()
        email = "test@example.com"
        role = "OWNER"
        
        token = create_access_token(
            user_id=str(user_id),
            scopes=[f"role:{role}", f"email:{email}"]
        )
        
        assert isinstance(token, str)
        assert len(token) > 0
        
        # Decode and verify
        payload = decode_token(token)
        assert payload["sub"] == str(user_id)
        assert f"role:{role}" in payload["scopes"]
        assert f"email:{email}" in payload["scopes"]

    def test_create_access_token_with_extra_claims(self):
        """Test JWT token creation with extra claims."""
        user_id = uuid4()
        email = "test@example.com"
        role = "ACCOUNTANT"
        tenant_id = str(uuid4())
        custom = "value"
        
        token = create_access_token(
            user_id=str(user_id),
            scopes=[
                f"role:{role}", 
                f"email:{email}",
                f"tenant_id:{tenant_id}",
                f"custom:{custom}"
            ]
        )
        
        payload = decode_token(token)
        assert payload["sub"] == str(user_id)
        assert f"role:{role}" in payload["scopes"]
        assert f"email:{email}" in payload["scopes"]
        assert f"tenant_id:{tenant_id}" in payload["scopes"]
        assert f"custom:{custom}" in payload["scopes"]

    def test_decode_token_valid(self):
        """Test decoding a valid token."""
        user_id = uuid4()
        email = "test@example.com"
        role = "OWNER"
        
        token = create_access_token(
            user_id=str(user_id),
            scopes=[f"role:{role}", f"email:{email}"]
        )
        
        payload = decode_token(token)
        assert payload["sub"] == str(user_id)
        assert f"role:{role}" in payload["scopes"]
        assert f"email:{email}" in payload["scopes"]

    def test_decode_token_expired(self):
        """Test decoding an expired token."""
        # Create an expired token
        expires_delta = timedelta(minutes=-15)  # Expired 15 minutes ago
        expire = datetime.now(timezone.utc) + expires_delta
        to_encode = {
            "exp": expire,
            "sub": "test@example.com",
            "role": "OWNER",
            "user_id": str(uuid4())
        }
        encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
        
        # Attempt to decode should raise an exception
        with pytest.raises(jwt.ExpiredSignatureError):
            decode_token(encoded_jwt)

    def test_decode_token_invalid_signature(self):
        """Test decoding a token with invalid signature."""
        to_encode = {
            "exp": datetime.now(timezone.utc) + timedelta(minutes=15),
            "sub": "test@example.com",
            "role": "OWNER",
            "user_id": str(uuid4())
        }
        # Encode with a different secret
        encoded_jwt = jwt.encode(to_encode, "wrong-secret", algorithm=ALGORITHM)
        
        with pytest.raises(jwt.InvalidSignatureError):
            decode_token(encoded_jwt)

    def test_decode_token_missing_role(self):
        """Test decoding a token missing role claim."""
        to_encode = {
            "exp": datetime.now(timezone.utc) + timedelta(minutes=15),
            "sub": "test@example.com",
            "user_id": str(uuid4())
            # Missing role
        }
        encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
        
        payload = decode_token(encoded_jwt)
        # The decode_token function does not validate claims, it just decodes.
        # So it will return the payload without role.
        assert "role" not in payload
        assert payload["sub"] == "test@example.com"

    # Note: AccountResolver and resolve_origin_state_code are not part of auth service.
    # They will be tested in their respective modules (Chart of Accounts and Company).