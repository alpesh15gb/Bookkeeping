# ApexBooks Complete UX, Architecture & Screen Refactoring Plan

## Codebase Size

- **412 Dart files**
- **100 screen files**
- **34 state management files** (notifiers, controllers, providers)
- **65 service/repository files**
- **35 tests files** (existing)

## Phase 1 — Research Summary

### Industry patterns observed across 10 platforms

| Pattern | Prevalence | ApexBooks Status |
|---------|-----------|-----------------|
| Left navigation rail | 8/10 | ✅ Implemented but needs refinement |
| Dashboard KPI cards | 9/10 | ✅ Has `ApexKpiCard` |
| Global search | 8/10 | ❌ `CommandPalette` exists but not global |
| Quick create menu | 7/10 | ⚠️ Present in home shell |
| List-detail navigation | 9/10 | ⚠️ Partially implemented |
| Inline editing | 5/10 | ❌ Not present |
| Batch operations | 7/10 | ❌ Not present |
| Breadcrumbs | 6/10 | ⚠️ `Breadcrumbs` widget exists |
| Dark mode | 8/10 | ⚠️ Foundation exists |
| Keyboard shortcuts | 7/10 | ⚠️ Partially implemented |
| Skeleton loading | 6/10 | ❌ Not implemented |
| Empty states with illustrations | 7/10 | ⚠️ Basic text only |
| Progressive disclosure | 6/10 | ❌ Not present |
| Drag-and-drop | 4/10 | ❌ Not present |

### Priority UX improvements identified

1. **Dashboard** — Currently fires 5 concurrent API calls with mixed offline support
2. **Invoice creation** — Most-used workflow, needs line-item efficiency
3. **Search** — Client-side only, no debounce, no global search
4. **Form validation** — Submit-time only, needs inline validation
5. **Empty states** — Inconsistent across screens
6. **Navigation** — No breadcrumbs, no recent items, no keyboard nav
7. **Tables** — Not virtualized, no column customization, no batch actions
8. **Mobile optimization** — Some screens don't adapt properly
9. **Sync visibility** — Per-record sync status missing from most lists
10. **Error handling** — Inconsistent error presentation

## Phase 3 — Screen Audit

### Screen inventory by module

| Module | Screens | UX Issues | Priority |
|--------|---------|-----------|----------|
| **Auth** | 6 | ✅ Good, minimal changes needed | Low |
| **Dashboard** | 1 | No offline indicators, no sync status | **High** |
| **Sales/Invoices** | ~8 | Form needs line-item optimization | **High** |
| **Purchasing** | ~10 | Similar to sales, needs consistency | **High** |
| **Payments** | ~5 | Form needs simplification | High |
| **Inventory** | ~6 | Movement forms need streamlining | Medium |
| **Banking** | ~4 | Reconciliation needs clarity | Medium |
| **Accounting** | ~8 | Journal line entry needs efficiency | Medium |
| **Reports** | ~7 | Read-only, mostly presentational | Low |
| **Settings** | ~6 | Low risk, good for first migration | Low |
| **Contacts** | ~2 | Simple CRUD, already adequate | Low |
| **Products** | ~2 | Simple CRUD, already adequate | Low |
| **GST** | ~4 | Niche, minimal changes | Low |
| **Financial Statements** | ~5 | Read-only, mostly good | Low |

### High-priority screens for refactoring

1. `dashboard_screen.dart` — Add sync status, offline banner, KPI cards
2. `invoice_form_screen.dart` — Line item UX, validation, keyboard nav
3. `journal_form_screen.dart` — Line entry efficiency, auto-balance
4. `purchase_order_form_screen.dart` — Consistency with invoice form
5. `expense_form_screen.dart` — Streamline data entry
6. `reconciliation_detail_screen.dart` — Clarify matching workflow
7. `inventory_movement_screen.dart` — Improve quantity entry

## Phase 4 — Implementation Strategy

### Approach

1. **One screen at a time.** Complete each screen fully before moving on.
2. **No business logic changes.** Only presentation-layer modifications.
3. **Reuse design system components** built in Phase 3.
4. **Verify after each screen** — analyzer clean, tests pass, offline works.

### Screen migration order

```
Phase 4A — Settings screens (low risk, validates components)
  → Build confidence with the refactoring workflow
  → Settings screens are simple read-heavy forms

Phase 4B — Contacts & Products (simple CRUD)
  → Validate form components with real data

Phase 4C — Dashboard (high visibility)
  → Add sync status, offline indicators, KPI cards from design system

Phase 4D — Invoice creation (most-used workflow)
  → Biggest UX impact for users

Phase 4E — Purchase screens (consistency with invoices)

Phase 4F — Journal entry & Accounting

Phase 4G — Inventory & Banking

Phase 4H — Reports & remaining screens
```

### Per-screen migration checklist

```
[ ] Analyze current screen for UX issues
[ ] Identify reusable design system components
[ ] Refactor presentation layer
[ ] Add loading states (skeleton)
[ ] Add empty states (illustration + action)
[ ] Add error states (retry)
[ ] Add sync status display
[ ] Add responsive layout
[ ] Add keyboard navigation
[ ] Verify accessibility (contrast, touch targets, labels)
[ ] Run flutter analyze (zero new errors)
[ ] Run flutter test (no regressions)
[ ] Verify offline behavior
```

### What will NOT change

- Business logic in repositories
- Database schema or Drift tables
- Sync engine, outbox, checkpoint model
- API contracts or authentication
- Accounting rules (journal balancing, tax, inventory cost)
- Navigation shell architecture (home shell, router)
- Existing state management patterns (providers, notifiers)
- Offline-first architecture

## Verification Criteria

Each screen is complete when:

- [ ] All UX issues from the audit are addressed
- [ ] Design system components are used consistently
- [ ] Loading, empty, error states are implemented
- [ ] Responsive layout works on mobile, tablet, desktop
- [ ] Sync status is visible where applicable
- [ ] Keyboard navigation works
- [ ] `flutter analyze` has no new errors
- [ ] `flutter test` is fully green
- [ ] Offline behavior is verified (create → offline → restart → sync)

## Estimated Effort

| Phase | Screens | Effort |
|-------|---------|--------|
| 4A — Settings | ~6 | Low |
| 4B — Contacts/Products | ~4 | Low |
| 4C — Dashboard | 1 | Medium |
| 4D — Invoices | ~8 | High |
| 4E — Purchasing | ~10 | High |
| 4F — Accounting | ~8 | Medium |
| 4G — Inventory/Banking | ~10 | Medium |
| 4H — Reports | ~7 | Low |

Total: ~54 screens across 8 phases

## Current Phase 3 completion status

The following foundation is already built and verified:

- ✅ Design tokens (spacing, radius, elevation, typography, breakpoints)
- ✅ Light/dark theme with Material 3
- ✅ Shared components: `ApexButton`, `ApexCard`, `ApexKpiCard`, `ApexStatusBadge`, `ApexSyncBadge`, `ApexEmptyState`, `ApexErrorState`, `ApexPageState`
- ✅ Design system showcase screen
- ✅ 15 design system tests
- ✅ 109 existing tests unchanged
- ✅ Zero analyzer errors in design system code
