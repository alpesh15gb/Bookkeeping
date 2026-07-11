# ApexBooks — CLAUDE.md

## Project Context
ApexBooks is a multi-tenant accounting platform for Indian SMBs. Backend: Python/FastAPI. Frontend: Flutter (mobile/web/desktop).

## Design System
Always read DESIGN.md before making any visual or UI decisions.
All font choices, colors, spacing, and aesthetic direction are defined there.
Do not deviate without explicit user approval.
In QA mode, flag any code that doesn't match DESIGN.md.

## Architecture
- **State management:** Riverpod (flutter_riverpod + riverpod_annotation)
- **API client:** Dio with auth/tenant/idempotency/refresh interceptors
- **Caching:** CacheService (in-memory TTL + request dedup)
- **Data pattern:** Service → Provider → Screen (via AsyncValue)
- **All screens use real backend APIs** — no mock data, no fake services
- **Posting services** (ledger, payable, receivable, inventory) connect to `/accounting/journals` and `/inventory-adjustments`

## Performance Rules
- Use `ListView.builder()` — never `ListView()` for dynamic content
- Use `const` constructors wherever possible
- All lists must be server-side paginated (never load more than 100 items)
- Parallelize independent API requests
- Cache master data (contacts, products, accounts) with TTL
- Show loading/empty/error/offline states for every API-driven component

## Routing
Key routes are defined in `frontend/lib/core/routing/router.dart` via go_router.
