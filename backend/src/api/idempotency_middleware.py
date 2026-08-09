import datetime as dt
import gzip
import hashlib
import json
import logging
import re
import uuid

from fastapi import Request
from sqlalchemy import text
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse, Response as StarletteResponse

from src.core.database import SessionLocal, tenant_context
from src.core.idempotency import clear_inflight_claim, set_inflight_claim

logger = logging.getLogger("bookkeeping.idempotency")

IDEMPOTENT_METHODS = {"POST", "PUT", "PATCH", "DELETE"}

# Exact POST creates that can write accounting or stock facts. Read-like POST
# endpoints such as previews are deliberately not included.
_REQUIRED_POST_PATHS = {
    "/api/v1/invoices",
    "/api/v1/bills",
    "/api/v1/expenses",
    "/api/v1/inventory-adjustments",
    "/api/v1/payments/receipts",
    "/api/v1/payments/disbursements",
    "/api/v1/accounting/journals",
    "/api/v1/accounting/contra",
    "/api/v1/invoices/credit-notes",
    "/api/v1/invoices/debit-notes",
    "/api/v1/returns/sales",
    "/api/v1/returns/purchase",
}

# Every correction below can create a reversal/replacement journal and/or stock
# movement and is therefore just as retry-sensitive as a create.
_REQUIRED_MUTATION_PATTERNS = (
    re.compile(r"^/api/v1/(?:invoices|bills|expenses|inventory-adjustments)/[^/]+$"),
    re.compile(r"^/api/v1/invoices/(?:credit-notes|debit-notes)/[^/]+$"),
    re.compile(r"^/api/v1/payments/(?:receipts|disbursements)/[^/]+$"),
    re.compile(r"^/api/v1/returns/(?:sales|purchase)/[^/]+$"),
    re.compile(r"^/api/v1/accounting/journals/[^/]+$"),
    # Transitional endpoints remain protected until the router bootstrap removes
    # them from the public app. Keeping them here also protects direct unit use.
    re.compile(r"^/api/v1/payments/(?:receipts|disbursements)/[^/]+/cancel$"),
    re.compile(r"^/api/v1/accounting/journals/[^/]+/reverse$"),
    re.compile(r"^/api/v1/invoices/(?:credit-notes|debit-notes)/[^/]+/(?:finalize|cancel)$"),
    re.compile(r"^/api/v1/returns/(?:sales|purchase)/[^/]+/cancel$"),
    re.compile(r"^/api/v1/inventory-adjustments/[^/]+/(?:confirm|cancel)$"),
)


def _requires_mandatory_key(method: str, path: str) -> bool:
    method = method.upper()
    if method == "POST" and path in _REQUIRED_POST_PATHS:
        return True
    if method in IDEMPOTENT_METHODS:
        return any(pattern.match(path) for pattern in _REQUIRED_MUTATION_PATTERNS)
    return False


def _committed_replay_response(existing=None) -> JSONResponse:
    content = {
        "detail": "Request already completed; replaying idempotent result.",
        "code": "IDEMPOTENT_REPLAY",
    }
    if existing and existing.get("resource_type") and existing.get("resource_id"):
        content["resource_type"] = existing["resource_type"]
        content["resource_id"] = str(existing["resource_id"])
        content["detail"] = (
            "Request already completed; the original resource is returned "
            "instead of re-executing."
        )
    return JSONResponse(
        status_code=200,
        content=content,
        headers={"Idempotency-Replayed": "true"},
    )


def _stored_response(existing) -> StarletteResponse:
    stored_body = existing["response_body"] or ""
    content_type = existing["response_content_type"] or "application/json"
    headers = {"Idempotency-Replayed": "true"}
    if "application/json" in content_type:
        return JSONResponse(
            content=json.loads(stored_body),
            status_code=existing["response_status"],
            headers=headers,
        )
    return StarletteResponse(
        content=stored_body,
        status_code=existing["response_status"],
        media_type=content_type,
        headers=headers,
    )


class IdempotencyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method not in IDEMPOTENT_METHODS:
            return await call_next(request)

        path = str(request.url.path)
        key = request.headers.get("Idempotency-Key")
        if not key:
            from src.core.config import settings

            if settings.REQUIRE_IDEMPOTENCY_KEY and _requires_mandatory_key(
                request.method, path
            ):
                return JSONResponse(
                    status_code=428,
                    content={
                        "detail": (
                            "An Idempotency-Key header is required for this "
                            "financial mutation so retries can never create a duplicate."
                        ),
                        "code": "IDEMPOTENCY_KEY_REQUIRED",
                    },
                )
            return await call_next(request)

        tenant_id = request.headers.get("X-Tenant-ID")
        if not tenant_id:
            return await call_next(request)
        if len(key) > 255:
            return JSONResponse(
                status_code=400,
                content={"detail": "Idempotency-Key is too long."},
            )
        try:
            tenant_uuid = uuid.UUID(tenant_id)
        except ValueError:
            return JSONResponse(
                status_code=400,
                content={"detail": "Invalid X-Tenant-ID header format."},
            )

        request_body = await request.body()
        request_hash = hashlib.sha256(request_body).hexdigest()
        claim = {
            "key": key,
            "tenant": tenant_id,
            "method": request.method,
            "path": path,
        }
        tenant_token = tenant_context.set(tenant_uuid)
        db = SessionLocal()
        owns_record = False
        inflight_token = None
        try:
            result = db.execute(
                text(
                    "INSERT INTO idempotency_keys "
                    "(id, idempotency_key, tenant_id, method, path, request_hash, "
                    "status, is_processed, created_at) "
                    "VALUES (:id, :key, :tenant, :method, :path, :request_hash, "
                    "'PROCESSING', false, CURRENT_TIMESTAMP) "
                    "ON CONFLICT (idempotency_key, tenant_id, method, path) DO NOTHING"
                ),
                {
                    "id": str(uuid.uuid4()),
                    "key": key,
                    "tenant": tenant_id,
                    "method": request.method,
                    "path": path,
                    "request_hash": request_hash,
                },
            )
            db.commit()

            if result.rowcount == 0:
                existing = db.execute(
                    text(
                        "SELECT request_hash, status, response_status, response_body, "
                        "response_content_type, created_at, resource_type, resource_id "
                        "FROM idempotency_keys "
                        "WHERE idempotency_key=:key AND tenant_id=:tenant "
                        "AND method=:method AND path=:path"
                    ),
                    {
                        "key": key,
                        "tenant": tenant_id,
                        "method": request.method,
                        "path": path,
                    },
                ).mappings().first()

                if existing and existing["status"] == "PROCESSING":
                    from src.core.config import settings

                    age = dt.datetime.now(dt.timezone.utc) - existing["created_at"]
                    if age > dt.timedelta(seconds=settings.IDEMPOTENCY_STALE_SECONDS):
                        db.execute(
                            text(
                                "DELETE FROM idempotency_keys "
                                "WHERE idempotency_key=:key AND tenant_id=:tenant "
                                "AND method=:method AND path=:path AND status='PROCESSING'"
                            ),
                            {
                                "key": key,
                                "tenant": tenant_id,
                                "method": request.method,
                                "path": path,
                            },
                        )
                        db.commit()
                        return await self.dispatch(request, call_next)
                    return JSONResponse(
                        status_code=409,
                        content={
                            "detail": "A request with this idempotency key is still processing.",
                            "code": "REQUEST_IN_PROGRESS",
                        },
                    )

                if (
                    existing
                    and existing["request_hash"]
                    and existing["request_hash"] != request_hash
                ):
                    return JSONResponse(
                        status_code=422,
                        content={
                            "detail": (
                                "Idempotency-Key was already used with a different "
                                "request payload."
                            ),
                            "code": "IDEMPOTENCY_PAYLOAD_MISMATCH",
                        },
                    )

                if existing and existing["status"] == "COMMITTED":
                    if existing["response_status"] is not None:
                        return _stored_response(existing)
                    return _committed_replay_response(existing)

                if (
                    existing
                    and existing["status"] == "COMPLETED"
                    and existing["response_status"] is not None
                ):
                    return _stored_response(existing)

                return JSONResponse(
                    status_code=409,
                    content={
                        "detail": "A request with this idempotency key is still processing.",
                        "code": "REQUEST_IN_PROGRESS",
                    },
                )

            owns_record = True
            inflight_token = set_inflight_claim(claim)
        except Exception:
            db.rollback()
            logger.exception(
                "Idempotency infrastructure failure; refusing to execute the "
                "request unprotected (key=%s path=%s)",
                key,
                path,
            )
            tenant_context.reset(tenant_token)
            return JSONResponse(
                status_code=503,
                content={
                    "detail": (
                        "Idempotency infrastructure is unavailable. The request "
                        "was NOT executed; retry later with the same Idempotency-Key."
                    ),
                    "code": "IDEMPOTENCY_UNAVAILABLE",
                },
            )
        finally:
            db.close()

        try:
            response = await call_next(request)
        except Exception:
            if owns_record:
                cleanup_token = tenant_context.set(tenant_uuid)
                cleanup = SessionLocal()
                try:
                    cleanup.execute(
                        text(
                            "DELETE FROM idempotency_keys "
                            "WHERE idempotency_key=:key AND tenant_id=:tenant "
                            "AND method=:method AND path=:path AND status='PROCESSING'"
                        ),
                        {
                            "key": key,
                            "tenant": tenant_id,
                            "method": request.method,
                            "path": path,
                        },
                    )
                    cleanup.commit()
                finally:
                    cleanup.close()
                    tenant_context.reset(cleanup_token)
            tenant_context.reset(tenant_token)
            raise
        finally:
            if inflight_token is not None:
                clear_inflight_claim(inflight_token)

        body = b"".join([chunk async for chunk in response.body_iterator])
        storage_body = body
        if response.headers.get("content-encoding", "").lower() == "gzip":
            storage_body = gzip.decompress(body)

        if owns_record:
            storage_token = tenant_context.set(tenant_uuid)
            store = SessionLocal()
            try:
                if response.status_code >= 500:
                    store.execute(
                        text(
                            "DELETE FROM idempotency_keys "
                            "WHERE idempotency_key=:key AND tenant_id=:tenant "
                            "AND method=:method AND path=:path"
                        ),
                        {
                            "key": key,
                            "tenant": tenant_id,
                            "method": request.method,
                            "path": path,
                        },
                    )
                else:
                    store.execute(
                        text(
                            "UPDATE idempotency_keys "
                            "SET status='COMPLETED', is_processed=true, "
                            "response_status=:response_status, response_body=:response_body, "
                            "response_content_type=:content_type "
                            "WHERE idempotency_key=:key AND tenant_id=:tenant "
                            "AND method=:method AND path=:path"
                        ),
                        {
                            "key": key,
                            "tenant": tenant_id,
                            "method": request.method,
                            "path": path,
                            "response_status": response.status_code,
                            "response_body": storage_body.decode("utf-8", errors="strict"),
                            "content_type": (
                                response.media_type
                                or response.headers.get("content-type")
                            ),
                        },
                    )
                store.commit()
            finally:
                store.close()
                tenant_context.reset(storage_token)

        tenant_context.reset(tenant_token)
        headers = dict(response.headers)
        headers.pop("content-length", None)
        return StarletteResponse(
            content=body,
            status_code=response.status_code,
            headers=headers,
            media_type=response.media_type,
        )


# Compose the public mutation contract after the legacy router modules are
# loaded but before main.py attaches the routers to FastAPI.
from src.api.v1.direct_posting_contract import install_direct_posting_contract
from src.api.v1.direct_posting_contract_ext import (
    install_extended_direct_posting_contract,
)

install_direct_posting_contract()
install_extended_direct_posting_contract()
