import logging
import uuid
import hashlib
import json
import gzip
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse, Response as StarletteResponse
from sqlalchemy import text
from src.core.database import SessionLocal, tenant_context

logger = logging.getLogger("bookkeeping.idempotency")

IDEMPOTENT_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


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
        tenant_token = tenant_context.set(uuid.UUID(tenant_id))
        db = SessionLocal()
        owns_record = False
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
                    "SELECT request_hash, status, response_status, response_body, response_content_type, created_at "
                    "FROM idempotency_keys WHERE idempotency_key=:key AND tenant_id=:tenant "
                    "AND method=:method AND path=:path"
                ), {"key": idempotency_key, "tenant": tenant_id, "method": request.method, "path": str(request.url.path)}).mappings().first()
                if existing and existing["status"] == "PROCESSING":
                    # Detect stale processing records (older than 60s) and delete+retry
                    import datetime as dt
                    now = dt.datetime.now(dt.timezone.utc)
                    age = now - existing["created_at"]
                    if age > dt.timedelta(seconds=60):
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
        except Exception:
            db.rollback()
            logger.exception("Idempotency check failed, allowing request to proceed")
        finally:
            db.close()
            tenant_context.reset(tenant_token)

        try:
            response = await call_next(request)
        except Exception:
            if owns_record:
                cleanup = SessionLocal()
                try:
                    cleanup.execute(text(
                        "DELETE FROM idempotency_keys WHERE idempotency_key=:key AND tenant_id=:tenant "
                        "AND method=:method AND path=:path AND status='PROCESSING'"
                    ), {"key": idempotency_key, "tenant": tenant_id, "method": request.method, "path": str(request.url.path)})
                    cleanup.commit()
                finally:
                    cleanup.close()
            raise

        body = b"".join([chunk async for chunk in response.body_iterator])
        storage_body = body
        if response.headers.get("content-encoding", "").lower() == "gzip":
            storage_body = gzip.decompress(body)
        if owns_record:
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
        headers = dict(response.headers)
        headers.pop("content-length", None)
        return StarletteResponse(
            content=body,
            status_code=response.status_code,
            headers=headers,
            media_type=response.media_type,
        )
