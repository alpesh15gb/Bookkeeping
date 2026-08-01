# ApexBooks UX Research & Redesign Plan

## Phase 1 — Competitive Analysis Summary

### Navigation patterns (industry standard)

| Platform | Primary Nav | Secondary | Screen Density |
|----------|-----------|-----------|----------------|
| QuickBooks Online | Left rail (collapsible) | Top bar with search | Medium |
| Xero | Top tabs + sub-nav | Left menu for settings | High |
| Zoho Books | Left sidebar (expandable) | Breadcrumbs | Medium |
| TallyPrime | Keyboard-driven menu | Function keys | Very high |
| NetSuite | Center-out dashboard | Role-based tabs | High |

**Common patterns:**
- Left navigation rail with icons + labels (collapsible on mobile)
- Top bar with: company selector, search, sync status, user menu
- Dashboard as default landing with KPI cards
- List-detail pattern for transactions
- Modal/sheet for quick-create actions
- Breadcrumb navigation for deep hierarchies

### Existing ApexBooks UI Assessment

#### Navigation (`lib/features/home/home_shell.dart`)
- Responsive shell with BottomNavigationBar (mobile) and rail (desktop)
- Dynamic nav items filtered by `gstEnabled` flag
- Quick Create modal for common actions
- **Issues:** No breadcrumbs, no global search, no recent-items navigation, nav items not grouped by domain

#### Dashboard (`lib/features/dashboard/presentation/dashboard_screen.dart`)
- Fires 5 concurrent API calls via `Future.wait`
- Uses `AsyncValue<T>` per slice for partial loading
- **Issues:** No offline fallback, no sync status indicator on cards, no trend sparklines, no quick-action grid

#### Forms (invoice, purchase, journal, etc.)
- Mix of `ConsumerStatefulWidget` and `ConsumerWidget`
- Some use `StateNotifier` for state, others use local `setState`
- Validation is mostly on submit rather than inline
- **Issues:** Inconsistent form layouts, no auto-save, no draft indicators, no keyboard shortcuts on forms

#### Lists (invoice list, journal list, etc.)
- Mix of `FutureProvider`, `StreamProvider`, and direct API calls
- Some use `ApexFilterBar` for search
- **Issues:** No column sorting on mobile, no bulk actions, inconsistent pagination, no saved filters

#### Tables (`lib/core/tables/apex_data_table.dart`)
- Custom data table with sortable columns, pagination, toolbar
- **Issues:** Not virtualized for large datasets, no column resize/reorder, no inline editing

#### Search
- `ApexSearchBar` and `command_palette.dart` for command search
- Client-side filtering only (loads full dataset then filters)
- **Issues:** No server-side search, no debounced search, search doesn't persist across navigation

#### Empty states
- Some screens use `EmptyState` widget, others return raw text
- **Issues:** Inconsistent, no illustrations, no suggested actions on some empty screens

#### Syncing / Offline
- `SyncStatusIndicator` widget shows sync state
- `SyncSummary` provides status text (pending, offline, syncing, etc.)
- **Issues:** Sync indicator not visible on all screens, no per-record sync status in lists/detail

## Phase 2 — Design System

### Color Palette

```dart
// Light mode
--primary: #1A56DB;        // Professional blue
--primary-light: #E1EFFE;
--primary-dark: #1E429F;
--surface: #FFFFFF;
--surface-muted: #F3F4F6;
--surface-raised: #FFFFFF;
--border: #E5E7EB;
--text-primary: #111827;
--text-secondary: #6B7280;
--text-muted: #9CA3AF;
--success: #059669;
--warning: #D97706;
--danger: #DC2626;
--info: #2563EB;

// Dark mode
--primary: #3B82F6;
--surface: #111827;
--surface-muted: #1F2937;
--surface-raised: #374151;
--border: #374151;
--text-primary: #F9FAFB;
--text-secondary: #D1D5DB;
--text-muted: #9CA3AF;
```

### Typography Scale

```dart
--display-xl: 32px / 40px (dashboard KPIs)
--display-lg: 28px / 36px (page titles)
--heading-lg: 22px / 28px (section headers)
--heading-md: 18px / 24px (card titles)
--heading-sm: 15px / 20px (list item titles)
--body-lg: 15px / 22px  (form labels, table cells)
--body-md: 13px / 20px  (content text)
--body-sm: 12px / 16px  (helper text, badges)
--caption: 11px / 14px  (timestamps, metadata)
--tabular: (figures, amounts — tabular-nums feature)
```

### Spacing System (4px base)

```dart
--space-1: 4px
--space-2: 8px
--space-3: 12px
--space-4: 16px
--space-5: 20px
--space-6: 24px
--space-8: 32px
--space-10: 40px
--space-12: 48px
—space-16: 64px
```

### Elevation

```dart
--elevation-0: no shadow (page background)
--elevation-1: 0 1px 2px (cards, list items)
--elevation-2: 0 2px 8px (dropdowns, popovers)
—elevation-3: 0 4px 16px (dialogs, sheets)
--elevation-4: 0 8px 24px (modals, drawers)
```

### Component Architecture

All components follow this contract:

```dart
class ApexComponent extends StatelessWidget {
  const ApexComponent({
    super.key,
    this.variant = ApexVariant.primary,
    this.size = ApexSize.md,
    this.tone = ApexTone.default_,
    this.fullWidth = false,
    this.disabled = false,
    ...
  });
}
```

#### Button variants
- `ApexButton.primary` — filled (primary action)
- `ApexButton.secondary` — outlined (secondary action)
- `ApexButton.ghost` — text-only (tertiary action)
- `ApexButton.danger` — red (destructive action)
- `ApexButton.icon` — icon-only (toolbar, compact)
- Sizes: `sm`, `md`, `lg`

#### Card variants
- `ApexCard` — standard card with elevation-1
- `ApexCard.highlighted` — primary border (featured item)
- `ApexCard.danger` — red border (sync errors, overdue)
- `ApexCard.interactive` — hover/ink well for navigation

#### Input variants
- `ApexTextField` — text input with label, hint, error, helper
- `ApexSelect` — dropdown/autocomplete
- `ApexMoneyField` — currency input with formatting
- `ApexDateField` — date picker
- `ApexSearchField` — with debounced callback
- `ApexPhoneField` — phone input with country code

#### Status indicators
- `ApexBadge` — colored label (status, type)
- `ApexStatusDot` — colored dot (online/offline/reconciled)
- `ApexSyncBadge` — sync status with icon + label
- `ApexLifecycleBadge` — draft/posted/issued/voided

### Responsive Layout System

```dart
class ApexResponsive extends StatelessWidget {
  /// Returns the current breakpoint.
  static ApexBreakpoint of(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return ApexBreakpoint.mobile;
    if (width < 1024) return ApexBreakpoint.tablet;
    return ApexBreakpoint.desktop;
  }
}

enum ApexBreakpoint { mobile, tablet, desktop }

// Layout rules
mobile:  single column, bottom nav, full-width inputs, bottom sheets
tablet:  2-column grid, side rail collapsed, adaptive forms
desktop: multi-column, expanded rail, side panels, keyboard shortcuts
```

## Phase 3 — Navigation Redesign

### Proposed structure

```
[Top bar]
  Company name + switcher │ Global search │ Quick create │ Sync status │ User menu

[Left rail]
  📊 Dashboard
  💰 Sales               → Invoices, Orders, Customers, Payments
  📦 Purchasing          → Bills, Orders, Receipts, Suppliers  
  🏭 Inventory           → Stock, Movements, Transfers, Warehouses
  🏦 Banking             → Accounts, Statements, Reconciliation
  📋 Accounting          → Journal, Ledger, Reports
  👥 Contacts
  ⚙️ Settings            → Company, Financial Years, Users, Roles
```

### Navigation principles
1. **Three-click rule**: Any screen reachable in ≤ 3 clicks
2. **Context preservation**: List filters/search persist when navigating to detail and back
3. **Quick create**: `Ctrl+N` or `+` FAB opens quick-create sheet with: Invoice, Bill, Payment, Expense, Journal
4. **Recent items**: Recently viewed records shown in nav submenu
5. **Breadcrumbs**: Shown in top bar for deep navigation paths

## Phase 4 — Dashboard Redesign

### Dashboard widget layout

```
┌──────────────────────────────────────────────────────────────────┐
│  Good morning, [User]                    [Sync: Up to date]      │
├──────────┬──────────┬──────────┬──────────┬──────────┬──────────┤
│ Cash     │ Bank     │ Receiv.  │ Payables │ Sales    │ Profit   │
│ ₹2,45,000│ ₹85,00,000│ ₹12,30,000│ ₹8,50,000│ ₹45,000   │ ₹18,000  │
│ ▲ 12%    │ ▲ 3%     │ ▼ 5%     │ ▲ 2%     │ ▲ 8%     │ ▲ 15%    │
├──────────┴──────────┴──────────┴──────────┴──────────┴──────────┤
│ ┌─ Revenue chart ──────────┐ ┌─ Recent invoices ────────────────┐ │
│ │                          │ │ INV-001  Acme Corp    ₹12,000   │ │
│ │    ▁▃▅▇▆▄▃              │ │ INV-002  Beta Inc     ₹8,500    │ │
│ │                          │ │ INV-003  Gamma LLC   ₹24,000   │ │
│ └──────────────────────────┘ └─────────────────────────────────┘ │
│ ┌─ Quick actions ──────────┐ ┌─ Pending sync ──────────────────┐ │
│ │  + Invoice  + Payment    │ │  3 changes pending | Sync now   │ │
│ │  + Expense  + Journal    │ │  Last synced 2 min ago          │ │
│ └──────────────────────────┘ └─────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## Phase 5 — Workflow Optimization Priorities

### Critical (high user impact)
1. **Invoice creation**: Reduce from 4 screens to 2 (form → confirmation)
2. **Customer selection**: Inline autocomplete with recent-first ordering
3. **Line item entry**: Tab between fields, auto-calculate totals
4. **Search**: Global search with keyboard shortcut `Ctrl+F`

### High
5. **Form validation**: Inline real-time validation instead of submit-time
6. **List pagination**: Virtual scrolling for large datasets
7. **Bulk actions**: Multi-select in lists → batch approve/pay/delete
8. **Keyboard navigation**: Tab order, Enter to save, Escape to cancel

### Medium
9. **Empty states**: Illustration + action button on every empty screen
10. **Error states**: Consistent error cards with retry action
11. **Loading states**: Skeleton screens instead of spinners
12. **Sync visibility**: Per-record sync badge in lists and detail

### Low
13. **Theming**: Dark mode support
14. **Animations**: Subtle transitions between screens
15. **Typography**: Consistent type scale across all screens

## Implementation Strategy

### Screen-by-screen order

1. **Design tokens** (colors, spacing, typography, elevation) — no visual change, just infrastructure
2. **Shared components** (ApexButton, ApexCard, ApexTextField, etc.) — reusable widget library
3. **Dashboard** — showcase for all new components
4. **Invoice screens** (list → form → detail → issue) — most-used workflow
5. **Purchase screens** (orders → receipts → bills → payments)
6. **Inventory screens** (stock → movements → transfers → adjustments)
7. **Banking screens** (accounts → statements → reconciliation)
8. **Accounting screens** (journal → ledger → reports)
9. **Settings screens** (company → financial years → users → preferences)
10. **Mobile optimization** — full pass on all screens for small screens

### Rules per screen rewrite

1. Extract inline styles to theme tokens
2. Replace raw `Container` with `ApexCard`
3. Replace raw `TextButton`/`ElevatedButton` with `ApexButton`
4. Replace raw `TextField` with `ApexTextField`
5. Add `ApexSyncBadge` where sync data exists
6. Add skeleton loading states
7. Add error states with retry
8. Add empty states with action
9. Ensure responsive layout
10. Verify all existing functionality preserved

## Phase 6-10 — Quick Reference

| Area | Current State | Target |
|------|-------------|--------|
| **Mobile** | Bottom nav + drawers | Single-column drill-down, touch targets ≥ 44px |
| **Offline** | Sync indicator in header only | Per-record badges, offline banner, pending queue visible |
| **Accessibility** | Not evaluated | WCAG AA contrast, logical tab order, semantic labels |
| **Performance** | Some lists rebuild entire items | Keys, const constructors, lazy loading, ListView.builder everywhere |

## Next Steps

1. ✅ Review this UX research document
2. Prioritize screens for redesign
3. Implement shared component library (no visual change to screens yet)
4. Redesign screens one at a time, verifying after each
5. Run full test suite after every screen change

No business logic, repository, sync engine, or database schema changes are required for this redesign.
