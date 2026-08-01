# ApexBooks offline-first production audit

Date: 2026-07-31  
Scope: Flutter UI/UX, local persistence and synchronization, FastAPI sync
contract, web/PWA delivery, and automated release checks.

## Native release-gate update

The requested release scope is now Windows desktop and Android mobile; web is
excluded. The following blockers have been closed since the initial audit:
encrypted native SQLite with safe plaintext migration, secure offline session
restore, API health probing, bounded sync-history retention, tenant-scoped
reference snapshots, offline number leases, strict invoice/payment/stock
contracts, pull checkpoint safety, and an end-to-end goods-receipt contract.
Windows and Android release builds succeed. The full suites pass: 543 Flutter
tests and 451 backend tests (7 backend tests skipped).

The release decision remains **NO-GO** because six local repositories still
emit event types for which the backend has no handler:
`purchase_invoice.posted`, `sales_delivery.posted`, `sales_return.posted`,
`purchase_return.posted`, `credit_note.posted`, and `debit_note.posted`.
Several routed purchase, sales-fulfilment, returns, reports, and settings
screens also remain legacy network-first screens. Releasing them as
offline-capable would risk permanently pending documents or unavailable
screens when the API is down.

## Release decision

**NO-GO for an offline-first production claim.**

The current application is a hybrid: journals use the new local-first path,
but most routed sales, payment, purchase, inventory, and settings screens still
use the legacy network services. Several local-first repositories exist, but
they are not the implementations users reach from the application shell. In
addition, the backend does not handle eight event types those repositories
queue. A user can therefore see a successful local save that can never be
accepted by the server.

The fixes in this audit remove several data-scope and delivery-contract defects,
but the P0 items below must be completed and exercised end-to-end before release.

## Fixed during this audit

| Severity | Defect | Resolution |
| --- | --- | --- |
| Critical | The API returns `acknowledgements`, while non-journal pushers expected `acknowledged`; successful pushes were interpreted as failures. | Added one validated response parser used by every pusher. It also checks the matching event ID and surfaces acknowledgement errors. |
| Critical | A push cycle read pending rows from every company and could send company B records while company A was active. | Push selection and scheduling are now scoped to the active company. The server also rejects an event whose company differs from the authenticated tenant. |
| High | Push success/failure metadata was updated only for journals, leaving other local entities dirty or pending. | Added status handling for all currently defined offline entities. |
| High | Sync status was hard-coded online, omitted last-sync time, counted every company, and used nested infinite streams that could stop updating. | Replaced it with a company-scoped combined stream for operations, checkpoints, and connectivity. |
| High | Session restoration and initial sync raced during startup. | Sync starts only after a successful restore. |
| High | PWA JavaScript and service-worker shell files could be cached immutable for one year, pinning users to stale releases. | Non-hashed shell files now revalidate; only static/fingerprinted assets are immutable. |
| High | Mobile web lacked a viewport declaration and rendered at a desktop layout width, clipping the authentication form. | Added the viewport and corrected PWA name, description, colors, and orientation. |
| High | Registration hid a required company name outside the active form, allowed an empty name to be submitted, and did not refresh the password-strength indicator while typing. | Company fields start visible, the UI explicitly validates the name, the strength bar is reactive, and the API requires at least two characters. |

Primary implementation references:

- `frontend/lib/core/sync/sync_engine.dart`
- `frontend/lib/core/sync/sync_scheduler.dart`
- `frontend/lib/core/sync/sync_providers.dart`
- `frontend/lib/main.dart`
- `backend/src/api/v1/apexbooks_sync.py`
- `frontend/nginx.conf`
- `frontend/web/index.html`
- `frontend/web/manifest.json`

## P0 blockers

### 1. Route every business workflow through one offline-first repository

Evidence:

- `frontend/lib/features/screens.dart` exports the legacy sales invoices,
  payments, purchasing, and inventory screens.
- Startup initializes `journalRepositoryProvider`, but no invoice, payment,
  inventory, purchasing, returns, banking, or credit/debit repository.

Required acceptance:

- Create/edit/issue/post actions never require the network unless the business
  rule explicitly requires a server reservation or third-party action.
- Every routed list and detail screen reads local data immediately.
- A cold offline restart shows the same committed local records.
- Delete/cancel/reversal semantics are defined and queued, not silently local.

### 2. Implement the complete server event contract

The clients currently emit these event types without backend handlers:

- `bank_statement.imported`
- `credit_note.posted`
- `debit_note.posted`
- `purchase_receipt.posted`
- `purchase_invoice.posted`
- `sales_delivery.posted`
- `sales_return.posted`
- `purchase_return.posted`

Required acceptance:

- Publish a versioned event schema for every event.
- Validate payloads server-side and apply each event atomically and idempotently.
- Add contract tests that send the exact Flutter payload for every event.
- Treat unsupported types as a visible permanent failure with a recovery path.

### 3. Make server-to-device synchronization complete

`SyncEvent` is currently created by the sync endpoint, not by normal CRUD
endpoints. Changes performed by another device or the legacy online screens do
not reliably enter the pull stream. The Flutter pull side applies only reference
accounts/parties and journals.

Unknown pulled event types are logged and skipped while the checkpoint advances.
That permanently discards data for a client that does not yet understand a new
event.

Required acceptance:

- Every server mutation emits an outbox event in the same database transaction.
- Pull applicators cover every locally stored aggregate.
- Unsupported events halt/quarantine the checkpoint or use an explicitly
  backward-compatible snapshot mechanism.
- Test device A -> server -> device B for create, update, post, cancel/reverse,
  and delete/tombstone.

### 4. Support secure cold launch while offline

`AuthController.restore()` always calls `/auth/me` and `/auth/memberships`.
Network failure clears the stored session and returns to login. The app therefore
cannot reopen offline even with a previously valid session.

Required acceptance:

- Cache the minimum signed/validated user and membership snapshot.
- Define a bounded offline authorization window and revocation behavior.
- Distinguish unreachable server from invalid/expired/revoked credentials.
- Never erase a valid session merely because the network is unavailable.
- Add cold-start tests for airplane mode, expired access token with a valid
  refresh token, revoked membership, and changed active company.

### 5. Implement offline statutory/document number allocation

The local `number_allocations` table is consumed but no application flow fills
it. The invoice issue UI passes empty company/device/financial-year values in
places and tells the user to connect to request a range, but no range request
and download workflow exists.

Required acceptance:

- Server leases collision-free, company/series/financial-year/device scoped
  ranges.
- Client persists the lease before offering offline issue/post.
- Exhaustion, expiry, device replacement, cancelled documents, and financial
  year rollover have explicit behavior.
- Concurrent multi-device tests prove that issued numbers never collide.

### 6. Provide recovery for failed operations and conflicts

The global Sync Centre is explicitly “Phase 1 — informational only.” It shows
counts but no affected record, error detail, retry/discard action, or conflict
resolution. “Sync now” does not requeue permanent failures. Journal-specific
recovery exists, but the rest is incomplete.

Required acceptance:

- List each failed/conflicted operation with company, document, safe message,
  timestamp, attempts, and actionable resolution.
- Support retry after correction and a deliberate discard/rollback policy.
- Use server revisions or another defined concurrency token.
- Test simultaneous edits, number conflicts, deleted references, permission
  changes, and schema-version mismatch.

## P1 production risks

### Data protection

The local Drift SQLite/IndexedDB database is not encrypted. It contains
accounting records and personal/business data. Define the supported device
threat model, encrypt native storage where required, and document the web
storage limitation. Verify secure logout, company switching, backups, exports,
and device disposal.

### Background delivery

Synchronization is foreground-only. There is no Android/iOS background worker.
Define the product guarantee (“sync while app is open” versus eventual
background delivery), add platform workers if needed, and test process
termination/relaunch.

### Outbox retention

There is no general pruning policy for successfully synchronized operations or
resolved conflicts. Journal-specific deletion exists, but normal successful
rows can grow without bound. Add a retention policy with diagnostics/audit
requirements and database-size tests.

### Connectivity semantics

The UI treats the presence of a network interface as “online.” That does not
prove the API is reachable and is wrong for captive portals, DNS failures, or a
backend outage. Use a bounded authenticated health/reachability probe and label
states as “network available,” “server reachable,” and “syncing/failed.”

### Error experience and information disclosure

More than fifty screens render `error.toString()`/`err.toString()` directly.
This produces inconsistent messages and can expose transport or internal
details. Route user-facing errors through the existing error mapper, attach a
support correlation ID, and keep stack/transport details in telemetry only.

### Accessibility and responsive coverage

Run keyboard-only, focus-order, screen-reader/semantics, text scaling (200%),
contrast, touch-target, narrow mobile, tablet, and desktop checks on every
primary flow. Add golden/widget tests for authentication, empty/loading/error,
offline/pending/failed/conflict, and long localized values.

### Observability and operations

Add release-version, device ID, company-safe correlation IDs, queue age/depth,
oldest pending operation, per-event failure rates, checkpoint lag, database
migration failures, and crash reporting. Never log tokens or business payloads.
Create alerts and a rollback/runbook for a bad client or event schema release.

## Validation completed

- Flutter static analysis: no issues.
- Flutter test suite: 540 tests passed.
- Flutter release web build: succeeded.
- Full backend suite: 446 passed, 7 skipped (453 collected).
- Manual browser inspection: desktop authentication layout is sound. A
  post-build Chrome device-emulation capture confirmed a 390 x 844 CSS viewport,
  390 px document width, and a fully visible authentication card with no
  horizontal clipping.

Passing tests validate the implemented paths; they do not cover the disconnected
offline repositories or missing event/pull contracts described above.

## Minimum release gate

1. Complete P0 items 1–6.
2. Add a two-device, two-company, offline/online E2E matrix with forced process
   termination and deterministic network faults.
3. Prove upgrade/migration from the last production database and PWA cache.
4. Run the full Flutter/backend suites, web/mobile release builds, security
   review, accessibility pass, and backup/restore drill.
5. Perform a staged rollout with queue/checkpoint telemetry and a tested rollback
   procedure.
