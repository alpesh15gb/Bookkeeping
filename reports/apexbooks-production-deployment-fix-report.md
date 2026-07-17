# ApexBooks Production Deployment Readiness Fix Report

**Date:** 18 July 2026 (Asia/Calcutta)  
**Target:** `https://api.apexbooks.in`  
**Contract:** ApexBooks Integration Contract v1 (`integration-contract-v1`, `e31e965`)  
**Scope:** Deployment readiness, missing customer receiver, migration health gate, and existing-contract master-data delivery

## Outcome

The application changes required for deployment readiness are implemented and locally verified. The production deployment itself is **not complete** because this workspace has no production host/database access or deployment pipeline, and the required integration implementation is still uncommitted relative to remote `master` (`e31e965`). Live production verification continues to show zero integration paths and HTTP 404 for the required receiver URLs.

No frozen contract file, accounting logic, or existing order/payment business logic was changed.

## Routes

### Local deployable application

The generated local FastAPI OpenAPI document exposes:

| Method | Route | Status |
|---|---|---|
| `POST` | `/api/integrations/medusa/v1/orders` | Registered; existing implementation unchanged |
| `PATCH` | `/api/integrations/medusa/v1/orders/{external_order_id}` | Registered; existing implementation unchanged |
| `POST` | `/api/integrations/medusa/v1/payments/captured` | Registered; existing implementation unchanged |
| `POST` | `/api/integrations/medusa/v1/customers` | Added and registered |

The customer receiver uses the shared Contract v1 integration processor and therefore applies API-key authentication, HMAC verification, timestamp validation, tenant resolution, replay protection, idempotency, transactional rollback, and integration event logging.

### Production observation

Non-mutating checks against `https://api.apexbooks.in` returned:

| Check | Result |
|---|---|
| `GET /health` | `200`; database, schema, and Redis reported `ok` by the currently deployed application |
| `GET /openapi.json` | `200`; zero `/api/integrations/*` paths |
| `/api/integrations/medusa/v1/orders` | `404` |
| `/api/integrations/medusa/v1/payments/captured` | `404` |
| `/api/integrations/medusa/v1/customers` | `404` |

Production therefore has not received this integration build. Contract response behavior cannot be verified on the live host until the deployment is performed.

## Customer integration

Implemented `POST /api/integrations/medusa/v1/customers` with:

- strict `CustomerCreatedRequest` validation matching the frozen Contract v1 shape;
- source/customer ID consistency validation;
- shared tenant, API-key, HMAC, timestamp, replay, and idempotency processing;
- customer matching in contract order: supplied mapped ApexBooks ID, Medusa mapping, normalized GSTIN, then case-insensitive accounting email for customers without GSTIN;
- tenant-scoped collision rejection with `LIFECYCLE_CONFLICT`;
- canonical ApexBooks `Contact`, `SyncedCustomer`, and `integration_entity_map` persistence;
- normalized email and GSTIN, preserved E.164 phone, addresses, state, and credit terms;
- no password, login, or authentication-field writes;
- `integration_master_sync_audit` and `integration_event_log` entries in the business transaction;
- Contract v1 customer success envelope with `201` for creation and `200` for an update/replay.

## Migration status

| Item | Result |
|---|---|
| Local Alembic head | `20260718_0005` |
| Application required schema revision | Updated to `20260718_0005` |
| Migration bypass | None; equality validation remains enforced |
| Compose validation | `docker compose config --quiet` passed |
| Production migration | Not independently verified; public health reflects the older deployed application |

Deployment must run `alembic upgrade head` before starting the updated API and workers. The updated `/health` endpoint will return degraded/503 unless the database revision is exactly `20260718_0005`.

## ApexBooks → Medusa master-data dispatcher

The existing `webhook_events` durable queue is now used for the four frozen Contract v1 master-data events:

| Event | Medusa receiver path |
|---|---|
| `product.changed` | `PUT /api/integrations/apexbooks/v1/products/{source_id}` |
| `price.updated` | `PUT /api/integrations/apexbooks/v1/prices/{source_id}` |
| `inventory.updated` | `PUT /api/integrations/apexbooks/v1/inventory/{source_id}` |
| `customer.updated` | `PUT /api/integrations/apexbooks/v1/customers/{source_id}` |

Behavior:

- the validated Contract v1 payload is queued in the same transaction as the master synchronization;
- a Celery Beat schedule scans pending Cartunez master events every 30 seconds;
- the worker sends the exact serialized body used to calculate HMAC-SHA256;
- tenant ID and HMAC secret come from the enabled `integration_connections` row;
- successful Contract envelopes mark the queue row `DELIVERED`;
- HTTP `408`, `429`, `500`, `502`, `503`, `504` and transport failures are retried;
- delays follow Contract v1: 60, 300, 900, 3600, 21600, then 86400 seconds within the 259200-second maximum window;
- permanent/exhausted failures become `FAILED` and create an encrypted `integration_dead_letter` entry;
- every attempt writes an `integration_event_log` row with `direction=OUTBOUND`, request/response hashes, response status, duration, and error code.

The deployment definition now includes a dedicated Celery Beat service in addition to the existing worker.

Required outbound environment variables:

```dotenv
CARTUNEZ_MEDUSA_BASE_URL=https://<medusa-production-origin>
CARTUNEZ_MEDUSA_API_KEY=<32-to-256-character Medusa receiver API key>
CARTUNEZ_OUTBOUND_ENABLED=true
CARTUNEZ_DELIVERY_TIMEOUT_SECONDS=15
CARTUNEZ_DELIVERY_BATCH_SIZE=25
```

`CARTUNEZ_MEDUSA_BASE_URL` is validated as HTTPS. Outbound delivery remains disabled by default until production credentials and the Medusa URL are supplied.

## Production configuration verification

### Verified in code/tests

- an enabled `integration_connections` row is required for integration name `cartunez`;
- API keys are compared using the stored SHA-256 hash;
- the HMAC secret must decrypt successfully using the deployment `SECRET_KEY`;
- the external tenant ID is used for `X-Tenant-Id` and must match the event payload;
- inbound tenant resolution maps `external_tenant_id` to the internal tenant UUID;
- outbound delivery fails closed when the connection, Medusa origin, API key, tenant match, or HMAC secret is unavailable.

### Not verified in production

No production `DATABASE_URL`, SSH key, host access, or deployment control plane is available in this workspace. The local `.env` is a development configuration and contains no Cartunez outbound variables. Therefore the following production values could not be inspected:

- existence and enabled status of the Cartunez `integration_connections` row;
- internal tenant mapping and non-deleted tenant state;
- API-key hash validity against the secret held by Medusa;
- HMAC secret decryption with the production `SECRET_KEY`;
- exact external tenant ID;
- Medusa production API origin and receiver API key.

No secret value was printed or copied into this report.

## Verification results

| Verification | Result |
|---|---|
| Frozen Contract v1 tree | Unchanged (`git diff -- docs/apexbooks/v1` clean) |
| Python compilation | Passed |
| Alembic single head | Passed: `20260718_0005` |
| Docker Compose rendering | Passed |
| Local OpenAPI required routes | Passed: all four registered with correct methods |
| Cartunez integration suite | **48 passed** |
| Customer create/replay/signature tests | Passed |
| Outbound signing/logging/retry tests | Passed |
| Full backend suite | **435 passed, 7 skipped, 1 failed** |

The single full-suite failure is outside this change: `tests/test_premerge_verification.py::TestBillCreationBothModes::test_bill_non_gst` expected a CGST rate of 9 for a non-GST bill but received 0. Accounting behavior was not modified because it is explicitly outside scope.

## Files changed for this readiness fix

- `backend/src/integrations/cartunez/customer_schemas.py`
- `backend/src/integrations/cartunez/customer_service.py`
- `backend/src/integrations/cartunez/customer_routes.py`
- `backend/src/integrations/cartunez/outbound.py`
- `backend/src/integrations/cartunez/master_service.py`
- `backend/src/integrations/cartunez/tests/test_deployment_readiness.py`
- `backend/src/core/config.py`
- `backend/src/main.py`
- `backend/src/workers/tasks.py`
- `docker-compose.yml`
- `reports/apexbooks-production-deployment-fix-report.md`

## Remaining deployment blockers

1. **Publish/deploy the integration build.** Remote `master` remains at frozen-contract commit `e31e965`; this working tree contains substantial pre-existing uncommitted work, so it was not safe to create or push a deployment commit without an identified release pipeline and confirmed change set.
2. **Run migrations.** Apply through `20260718_0005` before starting the updated application.
3. **Provision/verify `integration_connections`.** Confirm exactly one enabled Cartunez connection for the intended tenant, the external tenant ID, API-key hash, and decryptable HMAC secret.
4. **Provide the Medusa production URL and receiver API key.** Neither is available in this workspace.
5. **Enable outbound delivery.** Set `CARTUNEZ_OUTBOUND_ENABLED=true` only after the Medusa receiver and credentials are verified.
6. **Start API, worker, and Beat services.** All three are required for inbound routes and outbound queue delivery.
7. **Repeat live checks.** Confirm production OpenAPI paths, non-404 Contract errors for unsigned probes, exact schema health, and an authorized synthetic end-to-end request.
8. **Resolve or formally waive the unrelated accounting regression** before treating the complete backend suite as green.

## Deployment verification commands

Run from the production release environment without printing secrets:

```bash
alembic upgrade head
alembic current
docker compose up -d --build backend worker beat
curl -fsS https://api.apexbooks.in/health
curl -fsS https://api.apexbooks.in/openapi.json
```

Expected post-deployment conditions:

- Alembic current revision is `20260718_0005`;
- `/health` returns `200` with `schema: ok`;
- live OpenAPI contains the four routes listed above;
- unsigned requests return a JSON Contract v1 `AUTH_FAILED` response rather than `404`;
- authorized requests resolve the intended tenant and write inbound/outbound integration logs.

## Final status

**Application readiness fixes: complete locally.**  
**Production deployment and secret/tenant verification: blocked by unavailable production access and missing Medusa configuration.**
