import logging
import uuid
import hashlib
import json
import gzip
import datetime as dt
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse, Response as StarletteResponse
from sqlalchemy import text
from src.core.database import SessionLocal, tenant_context
from src.core.idempotency import (
    clear_inflight_claim,
    set_inflight_claim,
)

logger = logging.getLogger("bookkeeping.idempotency")

IDEMPOTENT_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


def _committed_replay_response(existing=None) -> JSONResponse:
    """Replay for a request whose financial transaction committed but whose
    response was never stored (the process died in between).  Returns the
    original resource identity when the commit marker captured it, so clients
    can recover the invoice/payment/bill id instead of a generic message."""
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


class IdempotencyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method not in IDEMPOTENT_METHODS:
            return await call_next(request)

        idempotency_key = request.headers.get("Idempotency-Key")
        if not idempotency_key:
            return await call_next(request)

        tenant_id = request.headers.get("X-Tenant-ID")
        if not tenant_id:
            return await call_next(request)
        if len(idempotency_key) > 255:
            return JSONResponse(status_code=400, content={"detail": "Idempotency-Key is too long."})

        try:
            uuid.UUID(tenant_id)
        except ValueError:
            return JSONResponse(
                status_code=400,
                content={"detail": "Invalid X-Tenant-ID header format."},
            )

        request_body = await request.body()
        request_hash = hashlib.sha256(request_body).hexdigest()
        claim = {
            "key": idempotency_key,
            "tenant": tenant_id,
            "method": request.method,
            "path": str(request.url.path),
        }
        tenant_token = tenant_context.set(uuid.UUID(tenant_id))
        db = SessionLocal()
        owns_record = False
        inflight_token = None
        try:
            result = db.execute(
                text(
                    "INSERT INTO idempotency_keys "
                    "(id, idempotency_key, tenant_id, method, path, request_hash, status, is_processed, created_at) "
                    "VALUES (:id, :key, :tenant, :method, :path, :request_hash, 'PROCESSING', false, CURRENT_TIMESTAMP) "
                    "ON CONFLICT (idempotency_key, tenant_id, method, path) DO NOTHING"
                ),
                {
                    "id": str(uuid.uuid4()),
                    "key": idempotency_key,
                    "tenant": tenant_id,
                    "method": request.method,
                    "path": str(request.url.path),
                    "request_hash": request_hash,
                },
            )
            db.commit()

            if result.rowcount == 0:
                existing = db.execute(text(
                    "SELECT request_hash, status, response_status, response_body, response_content_type, created_at, "
                    "resource_type, resource_id "
                    "FROM idempotency_keys WHERE idempotency_key=:key AND tenant_id=:tenant "
                    "AND method=:method AND path=:path"
                ), {"key": idempotency_key, "tenant": tenant_id, "method": request.method, "path": str(request.url.path)}).mappings().first()
                if existing and existing["status"] == "PROCESSING":
                    # A PROCESSING claim older than the stale threshold was
                    # abandoned before its business transaction committed (a
                    # committed financial transaction atomically flips the row
                    # to COMMITTED — see src/core/idempotency.py).  Claiming
                    # again is therefore safe; a still-running original would
                    # be aborted by the claim-lost guard instead of
                    # double-executing.
                    from src.core.config import settings
                    now = dt.datetime.now(dt.timezone.utc)
                    age = now - existing["created_at"]
                    if age > dt.timedelta(seconds=settings.IDEMPOTENCY_STALE_SECONDS):
                        db.execute(
                            text("DELETE FROM idempotency_keys WHERE idempotency_key=:key AND tenant_id=:tenant "
                                 "AND method=:method AND path=:path AND status='PROCESSING'"),
                            {"key": idempotency_key, "tenant": tenant_id, "method": request.method, "path": str(request.url.path)},
                        )
                        db.commit()
                        return await self.dispatch(request, call_next)  # Retry with fresh record
                    return JSONResponse(status_code=409, content={
                        "detail": "A request with this idempotency key is still processing.",
                        "code": "REQUEST_IN_PROGRESS",
                    })
                if existing and existing["request_hash"] and existing["request_hash"] != request_hash:
                    return JSONResponse(status_code=422, content={
                        "detail": "Idempotency-Key was already used with a different request payload.",
                        "code": "IDEMPOTENCY_PAYLOAD_MISMATCH",
                    })
                if existing and existing["status"] == "COMMITTED":
                    # The financial transaction committed but the process died
                    # before the response could be stored.  Replay the stored
                    # response when available; otherwise return the synthetic
                    # replay marker (with the captured resource identity when
                    # known) — never re-execute.
                    if existing["response_status"] is not None:
                        stored_body = existing["response_body"] or ""
                        content_type = existing["response_content_type"] or "application/json"
                        if "application/json" in content_type:
                            return JSONResponse(
                                content=json.loads(stored_body),
                                status_code=existing["response_status"],
                                headers={"Idempotency-Replayed": "true"},
                            )
                        return StarletteResponse(
                            content=stored_body,
                            status_code=existing["response_status"],
                            media_type=content_type,
                            headers={"Idempotency-Replayed": "true"},
                        )
                    return _committed_replay_response(existing)
                if existing and existing["status"] == "COMPLETED" and existing["response_status"] is not None:
                    stored_body = existing["response_body"] or ""
                    content_type = existing["response_content_type"] or "application/json"
                    if "application/json" in content_type:
                        return JSONResponse(
                            content=json.loads(stored_body),
                            status_code=existing["response_status"],
                            headers={"Idempotency-Replayed": "true"},
                        )
                    return StarletteResponse(
                        content=stored_body,
                        status_code=existing["response_status"],
                        media_type=content_type,
                        headers={"Idempotency-Replayed": "true"},
                    )
                return JSONResponse(status_code=409, content={
                    "detail": "A request with this idempotency key is still processing.",
                    "code": "REQUEST_IN_PROGRESS",
                })
            owns_record = True
            # Register the claim so the endpoint's first commit flips it to
            # COMMITTED atomically with the financial mutation.
            inflight_token = set_inflight_claim(claim)
        except Exception:
            db.rollback()
            # Fail CLOSED: a caller that supplied an Idempotency-Key gets a
            # 503 instead of an unprotected financial execution.  Running the
            # mutation without deduplication could double-post money movements
            # on retry, so the infrastructure failure must not silently
            # downgrade to no protection.
            logger.exception(
                "Idempotency infrastructure failure; refusing to execute the "
                "request unprotected (key=%s path=%s)",
                idempotency_key,
                str(request.url.path),
            )
            return JSONResponse(
                status_code=503,
                content={
                    "detail": "Idempotency infrastructure is unavailable. The request was NOT executed; retry later with the same Idempotency-Key.",
                    "code": "IDEMPOTENCY_UNAVAILABLE",
                },
            )
        finally:
            db.close()
            # tenant_context is intentionally left set here: ``call_next``
            # below runs the endpoint, whose sessions must open under this
            # tenant's RLS context (the after_begin listener applies SET
            # LOCAL from the ContextVar).  It is reset after the response.

        try:
            response = await call_next(request)
        except Exception:
            if owns_record:
                cleanup_token = tenant_context.set(uuid.UUID(tenant_id))
                cleanup = SessionLocal()
                try:
                    cleanup.execute(text(
                        "DELETE FROM idempotency_keys WHERE idempotency_key=:key AND tenant_id=:tenant "
                        "AND method=:method AND path=:path AND status='PROCESSING'"
                    ), {"key": idempotency_key, "tenant": tenant_id, "method": request.method, "path": str(request.url.path)})
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
            storage_token = tenant_context.set(uuid.UUID(tenant_id))
            store = SessionLocal()
            try:
                if response.status_code >= 500:
                    store.execute(text(
                        "DELETE FROM idempotency_keys WHERE idempotency_key=:key AND tenant_id=:tenant "
                        "AND method=:method AND path=:path"
                    ), {"key": idempotency_key, "tenant": tenant_id, "method": request.method, "path": str(request.url.path)})
                else:
                    store.execute(text(
                        "UPDATE idempotency_keys SET status='COMPLETED', is_processed=true, "
                        "response_status=:response_status, response_body=:response_body, "
                        "response_content_type=:content_type WHERE idempotency_key=:key "
                        "AND tenant_id=:tenant AND method=:method AND path=:path"
                    ), {
                        "key": idempotency_key, "tenant": tenant_id, "method": request.method,
                        "path": str(request.url.path), "response_status": response.status_code,
                        "response_body": storage_body.decode("utf-8", errors="strict"),
                        "content_type": response.media_type or response.headers.get("content-type"),
                    })
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
