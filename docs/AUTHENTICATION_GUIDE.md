# ApexBooks — Authentication Guide
> Complete guide for frontend developers to implement authentication, session management, and multi-tenancy.

---

## 1. Overview

ApexBooks uses **JWT Bearer tokens** with short-lived access tokens and longer-lived refresh tokens. Session state is client-side only (stateless JWT). Refresh token revocation uses Redis.

| Token | Lifetime | Storage |
|-------|----------|---------|
| Access Token | 15 minutes | Memory / sessionStorage |
| Refresh Token | 7 days | HttpOnly Cookie or localStorage (secure) |

---

## 2. Registration & Login Flow

### 2.1 Registration

```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "email": "owner@company.in",
  "password": "Secure@123",
  "full_name": "Ramesh Kumar",
  "phone_number": "+919876543210",
  "company_legal_name": "ABC Traders Pvt Ltd",
  "company_gstin": "29AABCT1332L1ZP",
  "company_pan": "AABCT1332L"
}
```

**Password requirements** (enforced by backend):
- Minimum 8 characters, maximum 128
- At least 1 uppercase letter
- At least 1 lowercase letter
- At least 1 digit
- At least 1 special character: `!@#$%^&*(),.?":{}<>-_=+[]\\/`

**Rate limit:** 5 requests/minute per IP

**On success (201):** Registration creates a User AND a Tenant in one call. The response is a `UserResponse` (not tokens). The user must then **login** to get tokens.

After registration: An email verification link is sent to the user. However, email verification is **not enforced** to use the API — it's advisory only.

### 2.2 Login

```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "email": "owner@company.in",
  "password": "Secure@123"
}
```

**Rate limit:** 10 requests/minute per IP

**On success (200):**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "expires_in": 900
}
```

**Store strategy:**
- `access_token`: Memory variable (React state / Zustand store)
- `refresh_token`: `localStorage` or HttpOnly cookie (rotate on each refresh)

### 2.3 Account Lockout

After repeated failed logins, the account is temporarily locked (`locked_until`). The API returns HTTP 401 with detail including the lockout duration. No specific lockout count is documented in the API.

---

## 3. Required Headers

Every authenticated request must include:

```http
Authorization: Bearer <access_token>
X-Tenant-ID: <tenant-uuid>
Content-Type: application/json
```

**`X-Tenant-ID`:** UUID of the active company/tenant. Obtained from `GET /auth/memberships`.

Without `Authorization` → HTTP 401 `{"detail": "Not authenticated."}`  
Without `X-Tenant-ID` → HTTP 422 `{"detail": "X-Tenant-ID header is required."}`  
Wrong tenant (not a member) → HTTP 403 `{"detail": "You are not a member of this tenant."}`

---

## 4. Token Refresh

### 4.1 Refresh Endpoint

```http
POST /api/v1/auth/refresh
Content-Type: application/json

{
  "refresh_token": "eyJ..."
}
```

**Rate limit:** 30 requests/minute

**On success (200):** Returns new `access_token` and `refresh_token` pair.

**On failure (401):** Token expired, invalid, or revoked.

### 4.2 Recommended Refresh Strategy

```
1. Make an API call with access_token
2. If response is 401:
   a. Attempt POST /auth/refresh with refresh_token
   b. If refresh succeeds → retry original request with new access_token
   c. If refresh fails (401) → clear all tokens → redirect to /login
3. Proactive refresh: set timer at (expires_in - 60) seconds before expiry
```

### 4.3 Axios Interceptor Pattern
```javascript
// Intercept 401 responses
axios.interceptors.response.use(
  response => response,
  async error => {
    if (error.response?.status === 401 && !error.config._retry) {
      error.config._retry = true;
      const { data } = await axios.post('/api/v1/auth/refresh', {
        refresh_token: getStoredRefreshToken()
      });
      setTokens(data.access_token, data.refresh_token);
      error.config.headers.Authorization = `Bearer ${data.access_token}`;
      return axios(error.config);
    }
    return Promise.reject(error);
  }
);
```

---

## 5. Logout

```http
POST /api/v1/auth/logout
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "refresh_token": "eyJ..."
}
```

**Effect:** Refresh token is revoked in Redis. Access token remains valid until expiry (15 min).

**Frontend action:** Clear all stored tokens, redirect to login.

---

## 6. Multi-Tenant (Multi-Company)

### 6.1 Get Memberships

```http
GET /api/v1/auth/memberships
Authorization: Bearer <access_token>
```

**Response:**
```json
[
  {
    "id": "membership-uuid",
    "tenant_id": "tenant-uuid-1",
    "role": "owner",
    "is_active": true
  },
  {
    "id": "membership-uuid-2",
    "tenant_id": "tenant-uuid-2",
    "role": "accountant",
    "is_active": true
  }
]
```

### 6.2 Company Switching

1. User selects company from dropdown
2. Frontend stores new `tenant_id` in state
3. All subsequent requests use the new `X-Tenant-ID`
4. **No re-login required** — the same access token works for all companies the user belongs to

### 6.3 Company Details

```http
GET /api/v1/companies/{tenant_id}
Authorization: Bearer <access_token>
X-Tenant-ID: {tenant_id}
```

---

## 7. JWT Token Structure

### Access Token Payload
```json
{
  "sub": "user-uuid-string",
  "type": "access",
  "scopes": ["tenant-uuid-string"],
  "exp": 1717000000
}
```

- `sub`: User UUID
- `type`: Always `"access"` for access tokens
- `scopes`: List of tenant UUIDs the user belongs to
- `exp`: Unix timestamp (15 minutes from issuance)

### Refresh Token Payload
```json
{
  "sub": "user-uuid-string",
  "type": "refresh",
  "exp": 1717604800
}
```

**Algorithm:** HS256  
**Secret:** Set via `JWT_SECRET_KEY` environment variable (min 32 chars in production)

---

## 8. Password Management

### 8.1 Change Password (authenticated)

```http
POST /api/v1/auth/change-password
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "current_password": "OldPass@123",
  "new_password": "NewPass@456"
}
```

**Rate limit:** 5 requests/minute

### 8.2 Forgot Password

```http
POST /api/v1/auth/forgot-password
Content-Type: application/json

{
  "email": "owner@company.in"
}
```

**Rate limit:** 3 requests/minute  
**Response:** Always 200 (prevents email enumeration): `{"detail": "If the email exists, a reset link has been sent."}`  
**Effect:** Sends email with reset link (valid for limited time).

### 8.3 Reset Password

```http
POST /api/v1/auth/reset-password
Content-Type: application/json

{
  "email": "owner@company.in",
  "token": "reset-token-from-email-link",
  "new_password": "NewSecure@789"
}
```

**Rate limit:** 5 requests/minute

---

## 9. Email Verification

```http
POST /api/v1/auth/verify-email?token=<verify-token>&email=<email>
```

**Rate limit:** 5 requests/minute  
**Effect:** Sets `email_verified = true`. Not required to use the API.

---

## 10. Two-Factor Authentication (TOTP)

### 10.1 Enable 2FA

```http
POST /api/v1/auth/2fa/enable
Authorization: Bearer <access_token>
```

**Rate limit:** 3 requests/minute  
**Response:**
```json
{
  "secret": "JBSWY3DPEHPK3PXP",
  "qr_code": "data:image/png;base64,...",
  "uri": "otpauth://totp/ApexBooks:owner@company.in?secret=JBSWY3DPEHPK3PXP&issuer=ApexBooks"
}
```

Display the QR code for the user to scan with Google Authenticator or similar.

### 10.2 Verify & Activate 2FA

```http
POST /api/v1/auth/2fa/verify
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "token": "123456"
}
```

**Rate limit:** 5 requests/minute  
**Response:** `{"detail": "2FA enabled successfully."}`

### 10.3 Disable 2FA

```http
POST /api/v1/auth/2fa/disable
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "token": "123456"
}
```

**Rate limit:** 3 requests/minute

> **Note:** The login flow does NOT currently enforce TOTP on login (no second-factor login step endpoint exists). 2FA setup is implemented but not yet integrated into the login challenge flow. See MISSING_APIS.md.

---

## 11. User Profile

### GET `/api/v1/auth/me`

```json
{
  "id": "uuid",
  "email": "owner@company.in",
  "full_name": "Ramesh Kumar",
  "phone_number": "+919876543210",
  "is_active": true,
  "email_verified": true,
  "totp_enabled": false,
  "created_at": "2025-04-01T10:00:00+00:00"
}
```

---

## 12. Idempotency

For **POST** and **PUT** requests that create or modify data, you can send an `Idempotency-Key` header to prevent duplicate submissions (e.g. network retry):

```http
POST /api/v1/invoices
Authorization: Bearer <token>
X-Tenant-ID: <uuid>
Idempotency-Key: a1b2c3d4-unique-key

{ ... invoice payload ... }
```

If the same key is used again within the idempotency window, the original response is returned without re-processing.

---

## 13. Rate Limiting

| Endpoint Group | Limit |
|----------------|-------|
| Login | 10/minute |
| Register | 5/minute |
| Forgot password | 3/minute |
| Reset/change password | 5/minute |
| 2FA enable | 3/minute |
| Reports / exports | 60/minute |
| All other API calls | 200/minute |

**Rate limit exceeded response (429):**
```json
{
  "error": "Rate limit exceeded.",
  "detail": "10 per 1 minute"
}
```

---

## 14. Security Headers

Every response includes:
```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'self'
```

---

## 15. CORS Configuration

Allowed origins (from `config.py`):
```
http://localhost:5173
http://localhost:3000
https://apexbooks.in
https://api.apexbooks.in
https://app.apexbooks.in
tauri://localhost
tauri://com.apexbooks.desktop
```

The `tauri://` origins support the desktop (Tauri) app.

---

## 16. GZip Compression

Responses larger than 500 bytes are automatically gzip-compressed.

Frontend should send: `Accept-Encoding: gzip` (most HTTP clients do this automatically).

---

## 17. Request ID

Every response includes: `X-Request-ID: <8-char-hex>` for debugging.

---

## 18. Health Check (No Auth)

```http
GET /health
```
```json
{
  "status": "healthy",
  "database": "ok",
  "redis": "ok",
  "timestamp": "2025-04-01T10:00:00+00:00"
}
```
