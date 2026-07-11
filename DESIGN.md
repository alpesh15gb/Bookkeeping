# Design System — ApexBooks

## Product Context
- **What this is:** ApexBooks — a multi-tenant accounting platform for Indian SMBs handling GST-compliant invoicing, expense tracking, e-Invoicing, GSTR filing, and double-entry bookkeeping.
- **Who it's for:** Business owners and accountants at Indian SMBs. The same app serves both types of user — owners need clarity and guided flows, accountants need density and efficiency.
- **Space/industry:** Indian SMB accounting and GST compliance. Competitors: Zoho Books, Vyapar, TallyPrime, BUSY, Khatabook, Marg ERP.
- **Project type:** Flutter app (mobile, web, desktop) + Vue.js web frontend (separate repo). This document covers the Flutter design system.
- **North Star:** **Speed, Simplicity, Trust** — every design decision serves these three words.

## Aesthetic Direction
- **Direction:** Industrial Precision — brutalist clarity with warmth. Every pixel earns its place.
- **Decoration level:** Minimal — typography and spacing do all the work. No gradient buttons, no decorative blobs, no 3-column icon grids. Color appears only when it carries meaning (invoice status, GST rate, payment overdue).
- **Mood:** Serious but not cold. Efficient but not rushed. Trustworthy but not boring. Software for people who run real businesses.
- **Reference sites:** Zoho Books (polished SaaS baseline), Stripe (clarity), Linear (data density), TallyPrime (category incumbent to differentiate from).

## Typography
- **Display/Headings:** Instrument Sans (weights 500/600/700) — more character than Inter while pairing harmoniously. Used for page titles, hero numbers (₹ amounts), section headers.
- **Body/UI:** Inter (weights 400/500/600/700) — already established in the codebase. Excellent readability, strong Flutter support via `google_fonts` package, good Devanagari coverage for Hindi.
- **UI/Labels:** Inter Semibold 14-15px for buttons, 12px uppercase for section labels in data tables.
- **Data/Tables:** JetBrains Mono with `tabular-nums` — financial data needs numbers that don't shift alignment. Used for invoice amounts, ledger entries, GST calculations, account balances.
- **Loading:** Google Fonts via `google_fonts` Flutter package. CDN-loaded at app startup with `GoogleFonts.interTextTheme()` and `GoogleFonts.getFont('Instrument Sans')`.
- **Scale:**
  - Caption: 11px (status badges, metadata)
  - Small: 12-13px (table cells, secondary text)
  - Body: 14-15px (paragraphs, input text)
  - Label: 15px bold (buttons)
  - Subtitle: 16-18px (card titles, section headers)
  - Title: 22-26px (page titles)
  - Hero: 32px+ (KPI values, financial totals)

## Color
- **Approach:** Balanced — indigo primary for trust with personality, purple accent for distinction. Semantic colors carry real meaning (green=paid, amber=pending, red=overdue, blue=info).
- **Primary:** `#4F46E5` (Indigo) — buttons, links, active states, selected items. Dark mode: `#818CF8`.
- **Primary Container:** `#E0E7FF` — selected rows, tag badges, filled chip backgrounds. Dark mode: `#3730A3`.
- **Accent:** `#7C3AED` (Purple) — highlights, premium feature badges, visual distinction. Dark mode: `#A78BFA`.
- **Neutrals (cool gray):**
  - Background/Page: `#F5F6FA` (`#0F1117` dark)
  - Surface (cards): `#FFFFFF` (`#1A1D27` dark)
  - Surface Muted (inputs, subtle fills): `#F5F6FA` (`#232734` dark)
  - Border: `#E5E7EB` (`#2C313F` dark)
  - Text Primary: `#111827` (`#F3F4F6` dark)
  - Text Secondary: `#4B5563` (`#CBD5E1` dark)
  - Text Muted: `#9CA3AF` (`#8590A2` dark)
- **Semantic:**
  - Success (Paid/Active): `#16A34A` / dark `#4ADE80`
  - Warning (Pending/Due soon): `#D97706` / dark `#FBBF24`
  - Danger (Overdue/Error): `#DC2626` / dark `#F87171`
  - Info (Neutral updates): `#0EA5E9` / dark `#38BDF8`
- **Dark mode:** Redesigns surfaces (deep navy: `#0F1117`, `#1A1D27`, `#232734`), not just inverted. Saturation dropped ~15% for readability. Shadows become stronger to maintain depth.

## Spacing
- **Base unit:** 4px, with 8px as the working increment for major gaps.
- **Density:** Comfortable for primary screens (dashboard, forms), compact for data-dense screens (ledgers, invoice lists) using `md: 12px` instead of `lg: 16px`.
- **Scale:**
  - `2xs — 4px` (tight icon/text spacing, table cell padding)
  - `sm — 8px` (gap between related elements)
  - `md — 12px` (compact gutters for data-dense screens)
  - `lg — 16px` (standard gap between cards/sections)
  - `xl — 24px` (section padding)
  - `xxl — 32px` (major section spacing)
  - `xxxl — 48px` (page-level padding)

## Layout
- **Approach:** Grid-disciplined — strict 8px grid, predictable alignment, data-dense tables. Accounting software lives and dies on scannability.
- **Grid:** Responsive breakpoints: mobile (<600px) → single column, tablet (600-940px) → 2-3 columns, desktop (>940px) → full multi-column. Data tables use fixed column widths for number alignment.
- **Max content width:** 1200px (desktop), full-bleed on mobile.
- **Border radius:**
  - `sm — 6px` (buttons, inputs, chips, small UI elements)
  - `md — 10px` (cards, panels, dialogs)
  - `lg — 14px` (large cards, modals)
  - `xl — 20px` (bottom sheets, top-level containers)
  - `pill — 999px` (status badges, avatar, toggle pills)

## Motion
- **Approach:** Minimal-functional — the only animations are ones that aid comprehension. 100-200ms transitions for status changes, page transitions, and data updates. No bounce, no parallax, no decorative entrance sequences.
- **Easing:** Enter: `ease-out` (fast in, slow out — feels responsive). Exit: `ease-in` (subtle fade). Move: `ease-in-out` (smooth position changes).
- **Duration:**
  - Micro (50-100ms): button press, hover state, checkbox toggle
  - Short (150-200ms): page transitions, dialog open, status badge change
  - Medium (250-400ms): panel expand, dropdown open
  - Long (400-700ms): never used for UI — reserved for splash/loading screens only

## Widget / Component Standards

### Data Tables
- Server-side pagination (25/50/100 per page), sort, and filter.
- Sticky header row with sort indicators.
- Compact rows on mobile (48px), standard on desktop (38px data row).
- Status badges with semantic colours (paid/green, pending/amber, overdue/red).
- Loading skeleton while data fetches. Empty state with action CTA when no data.
- Keyboard navigable (arrow keys, enter, escape).

### Cards
- `cardTheme`: no elevation, `surfaceRaised` background, `border`-colored border, `lg(14px)` radius.
- Box shadow: `0 1px 3px rgba(0,0,0,0.06)` only for emphasis cards.
- KPI cards: icon in 12%-opacity tone container, uppercase label, large value, optional footer.

### Buttons
- Primary: filled `primary` background, `onPrimary` text, `md(10px)` radius. Min height 48px.
- Outline: transparent background, `border`-colored border.
- Ghost: transparent, text only.
- All use Inter Semibold 15px, `md(10px)` radius, consistent horizontal padding.

### Forms
- Background: `surfaceMuted`. Border: `border` color. Focus: `primary` border + 3px glow.
- Error: `danger` border + error hint text below. Success/valid states optional.
- Dropdowns use entity selector pattern (searchable, paginated from API).

## Performance Principles
- `ListView.builder` preferred over `ListView` for any list with more than 5 items.
- `const` constructors everywhere possible to reduce widget rebuilds.
- API responses cached in-memory with TTL (30s for lists, 2min for detail).
- Concurrent API requests with error isolation (one failure never blanks the whole screen).
- Data tables use server-side pagination — never load more than 100 items at once.
- Master data (contacts, products, accounts) cached client-side with `CacheService` + request dedup.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-07-12 | Initial design system created | Created by /design-consultation based on product context, competitive research of Indian accounting software (Zoho Books, Vyapar, BUSY, TallyPrime, Khatabook, Marg ERP), and the user's north star: Speed, Simplicity, Trust. |
| 2026-07-12 | Instrument Sans chosen for Display over alternatives | Pairs well with established Inter body font. Has more character than Inter at display sizes while maintaining readability. Good weight range (500-700). |
| 2026-07-12 | JetBrains Mono for data/tables | Tabular-nums support critical for financial number alignment. Readable at small sizes (11-13px). |
| 2026-07-12 | Indigo (#4F46E5) primary + purple (#7C3AED) accent | Purple accent is a deliberate departure from category conventions (most accounting apps use blue or teal). Provides instant visual distinction while indigo maintains trust signals. |
| 2026-07-12 | Minimal decoration level | Every visual element needs a functional justification. Accounting software is information-dense — decoration competes with data. |
