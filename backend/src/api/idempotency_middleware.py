import logging
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
from sqlalchemy import text
from src.core.database import SessionLocal

logger = logging.getLogger("bookkeeping.idempotency")

IDEMPOTENT_METHODS = {"POST", "PUT", "PATCH"}


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

        db = SessionLocal()
        try:
            existing = db.execute(
                text(
                    "SELECT id FROM idempotency_keys "
                    "WHERE idempotency_key = :key AND tenant_id = :tenant AND method = :method AND path = :path"
                ),
                {
                    "key": idempotency_key,
                    "tenant": tenant_id,
                    "method": request.method,
                    "path": str(request.url.path),
                },
            ).fetchone()

            if existing:
                logger.warning(
                    "Duplicate idempotency key %s for %s %s (tenant=%s)",
                    idempotency_key, request.method, request.url.path, tenant_id,
                )
                return JSONResponse(
                    status_code=409,
                    content={
                        "detail": "This request has already been processed. Duplicate submission rejected.",
                        "code": "DUPLICATE_REQUEST",
                    },
                )

            db.execute(
                text(
                    "INSERT INTO idempotency_keys (idempotency_key, tenant_id, method, path) "
                    "VALUES (:key, :tenant, :method, :path)"
                ),
                {
                    "key": idempotency_key,
                    "tenant": tenant_id,
                    "method": request.method,
                    "path": str(request.url.path),
                },
            )
            db.commit()
        except Exception:
            db.rollback()
            logger.exception("Idempotency check failed, allowing request to proceed")
        finally:
            db.close()

        return await call_next(request)
