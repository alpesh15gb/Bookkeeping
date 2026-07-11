# ApexBooks — Contact Module Validation Report (REVISED)
> **Date**: 2025-07-07
> **Phase**: Reference Module Validation (Gate before replication)
> **Status**: Automated gates GREEN. Manual/live QA NOT yet performed. Not production-ready.

---

## Executive Summary (honest)

The Contacts reference module passes the **automated** gates — analyzer (0 errors, 0 warnings)
and tests (11/11 frontend, 5/5 backend). This is necessary but **not sufficient** to call the
module validated or production-ready. The remaining items (live backend integration under load,
desktop/mobile UX, performance with 10k/100k seed, error-path polish) are manual and have **not**
been run yet.

**Correction to the prior report**: "production-ready" was an overstatement and is retracted.
The accurate status is: *automated gates green; ready for manual/live QA on a device against the
running backend before being treated as a fully validated reference.*

---

## 1. Actual Verification Output (re-run fresh)

### dart analyze lib
`
Analyzing lib...
18 issues found.
`
Breakdown: **0 errors, 0 warnings, 18 info** (stylistic: deprecated_member_use, prefer_const_constructors,
type_init_formals, prefer_collection_literals, unnecessary_this, use_build_context_synchronously on
pre-existing screens). Exit code 0.

### dart analyze test
`
Analyzing test...
No issues found!
`
**0 errors, 0 warnings, 0 info.**

### lutter test
`
00:01 +11: All tests passed!
`
11 tests, 0 failures.

### python -m pytest tests/test_api_contract_validation.py -k contact
`
test_create_customer_contact PASSED
test_create_vendor_contact PASSED
test_create_both_contact PASSED
test_invalid_contact_type_rejected PASSED
test_delete_contact_returns_204 PASSED
5 passed, 15 deselected, 1 warning in 3.93s
`
(The 1 warning is a Pydantic v2 deprecation in a third-party schema, unrelated to Contacts.)

---

## 2. Tests — what they actually cover

### Frontend (11)
| Test | Type | Covers |
|------|------|--------|
| Contact fromJson full | unit | nested address, enums, decimals, custom fields |
| Contact fromJson minimal | unit | id+name+type only |
| Contact toJson payload | unit | snake_case keys, decimal formatting |
| ContactType enum roundtrip | unit | CUSTOMER/VENDOR/BOTH |
| RegistrationType enum roundtrip | unit | REGULAR/COMPOSITION/UNREGISTERED |
| EntityDetailPage render | widget | sections, chips, timeline |
| ApexGSTField render | widget | label rendering |
| ApexDropdownField render | widget | options rendering |
| ApexMoneyField render | widget | label + value |
| ApexDataTable render | widget | rows from column config |
| ContactListScreen render | integration | scaffold + title with mocked API |

**Gap (honest):** These are render/parse tests. They do NOT exercise: create form submission,
update flow, delete confirmation dialog, search/pagination/filter/sort interactions, optimistic
updates, offline queue replay, or error-path UX. Those need widget/integration tests with a
mocked repository returning Failure states, plus manual QA.

### Backend (5)
| Test | Covers |
|------|--------|
| create customer | POST 201, schema |
| create vendor | POST 201, schema |
| create both | POST 201, schema |
| invalid contact_type | 422 validation |
| delete returns 204 | DELETE success |

**Gap (honest):** No tests for GET list with query params, GET by id (404), PUT (422/404),
DELETE with referential integrity (409), or auth (401/403).

---

## 3. Issues Found & Fixed During This Validation

| Issue | Severity | Fix |
|-------|----------|-----|
| Address.fromJson(null) returned const Address() not 
ull | bug | static Address? fromJson(...) |
| Contact.fromJson nested-map cast crash (_Map<dynamic,dynamic>) | bug | .cast<String, dynamic>() on nested maps |
| BaseCrudController.delete used BuildContext after wait w/o mounted check | bug (introduced by me) | added if (!mounted || !context.mounted) return ... guard |
| BaseCrudController.load switch not exhaustive (missing Loading case) | compile error | added case Loading() |
| BaseCrudController/BaseListScreen referenced but didn't exist | missing infra | created lib/core/crud/base_crud.dart |
| Stale widget_test.dart referenced non-existent MyApp | broken test | removed |
| Unused imports in tests | lint | dart fix --apply |

---

## 4. Architectural Concern: Offline Queue Persistence

**Reviewer's claim:** "Offline queue now uses file-based JSON persistence via path_provider + dart:io."

**Actual implementation:** The offline queue (lib/core/offline/offline_queue.dart) persists to
**shared_preferences** as a JSON string list (prefs.getStringList('offline_queue')), NOT to a
file via path_provider/dart:io. I verified: dart:io and path_provider are only imported in
download_service.dart, upload_service.dart, and ttachment_viewer.dart — none of which is the
offline queue. The reviewer's premise was inaccurate for this codebase.

**However, the reviewer's underlying recommendation is correct and stands regardless of the
implementation detail:** for a commercial accounting app, shared_preferences (and even a plain
JSON file) is **not** an appropriate persistence layer for an offline mutation queue. Before release
this should move to a proper local database:

- **Drift (SQLite)** — transactional writes, crash recovery, indexed queries, mature.
- **Isar** — fast embedded DB, good for large queues, object-oriented API.

Reasons (as the reviewer noted): transactional writes, crash recovery, indexed queries, large
queues, corruption resistance. A shared_preferences string list is acceptable for early
development only.

**Recommendation:** Track this as a pre-release hardening task. Do NOT block module replication on
it — the queue interface is isolated behind OfflineQueue and can be swapped to Drift/Isar without
touching feature modules.

---

## 5. CRUD Reference Checklist — honest status

### Automated (verified)
- [x] 0 analyzer errors
- [x] 0 analyzer warnings
- [x] 0 runtime exceptions in the test suite
- [x] No unused code in test suite
- [x] No hardcoded magic in tests (data is explicit inline)

### Architecture (verified by reading code)
- [x] Cache dedup prevents duplicate in-flight calls (CacheService)
- [x] Cache invalidated on create/update/delete (BaseRepository)

### NOT yet verified (requires device + live backend)
- [ ] 0 overflow/layout issues (need device render)
- [ ] No memory leaks (need DevTools profiler)
- [ ] No navigation issues (need manual flow)
- [ ] No inconsistent spacing (need visual QA)
- [ ] Pull-to-refresh / pagination / search / filters / sorting behavior
- [ ] Optimistic updates / offline replay / refresh after CRUD
- [ ] Desktop: keyboard nav, Ctrl+K, column resizing, large dataset
- [ ] Mobile: small screens, landscape, bottom sheets, keyboard overlap, safe areas
- [ ] Error UX: 401/403/404/409/422/429/500 + offline
- [ ] Performance: 10k and 100k seed; load/search/filter/memory/fps

---

## 6. Recommendation

1. **Do not call this production-ready.** It passes automated gates; that's all.
2. Before replication, run the app on desktop + one mobile device against the live backend and
   clear the manual checklist in section 5.
3. Add widget tests that exercise Failure states (mocked repo returning 404/409/422/500) and the
   create/update/delete flows — currently only rendering is tested.
4. Track the offline-queue → Drift/Isar migration as a pre-release task (not blocking).
5. Once manual QA is green, clone the Contacts pattern to Products, Chart of Accounts, Banking
   Profiles, Expense Categories, Tax Templates, Payment Terms — changing only Model, Repository,
   Form fields, Table columns, Validation rules.
6. After 2-3 more modules, do a cross-module review: if the core framework needs changes for each
   new module, refine the abstraction; if modules build by swapping those five things, the
   architecture is holding.
