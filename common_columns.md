# Common Table Patterns Analysis

## Overview

Analysis of three list screens:
- `invoice_list_screen.dart` (242 lines)
- `expense_list_screen.dart` (94 lines)
- `payment_list_screen.dart` (141 lines)

---

## Common Structure (All Screens)

### 1. **StatefulWidget Pattern**
```dart
class XListScreen extends StatefulWidget {
  const XListScreen({super.key});
  @override
  State<XListScreen> createState() => _XListScreenState();
}
```

### 2. **Data Loading in initState**
All screens use the same pattern:
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    context.read<XProvider>().fetchX();
  });
}
```

### 3. **Provider Consumption**
```dart
final xProvider = context.watch<XProvider>();
final items = xProvider.items;
final isLoading = xProvider.isLoading;
```

### 4. **Layout Skeleton**
```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Header row (title + button)
    Row(...),
    const SizedBox(height: AppSpacing.lg),
    
    // Optional: filter chips row
    Row(...),
    const SizedBox(height: AppSpacing.lg),
    
    // Table container
    Expanded(
      child: isLoading && items.isEmpty
          ? Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? AppEmptyState(...)
              : AppTable(...),
    ),
  ],
)
```

---

## Common UI Components

### Header Row (100% duplication)
```dart
Row(
  children: [
    Text('Title', style: AppTypography.headlineLarge),
    const Spacer(),
    AppButton(label: '+ Item', icon: Icons.add, onPressed: () {}),
  ],
)
```

### Filter Chips (67% duplication - Invoice + Payment)
```dart
AppFilterChip(
  label: 'Label',
  count: itemCount,
  isSelected: selectedValue == 'VALUE',
  selectedColor: AppColors.xxx,
  onTap: () => setState(() => selectedValue = 'VALUE'),
)
```

### Table Structure (100% duplication)
```dart
AppTable(
  columns: const [
    TableColumn(label: 'Column 1', width: XXX),
    TableColumn(label: 'Column 2', width: XXX),
  ],
  rows: items.map((item) {
    return AppTableRow(
      onTap: () => ... ,  // optional
      backgroundColor: ... ,  // optional
      cells: [
        Text(item.field, style: AppTypography.xxx),
        AppAmountText(amount: item.amount, style: AppTypography.amountTiny),
        AppStatusBadge(status: ..., isCompact: true),
      ],
    );
  }).toList(),
)
```

---

## Date Formatting (100% duplication)

All three screens implement identical date formatting:

```dart
String _formatDate(String date) {
  if (date.isEmpty) return '-';
  try {
    final d = DateTime.parse(date);
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
  } catch (_) {
    return date;
  }
}
```

---

## Feature Comparison

| Feature                | Invoice | Expense | Payment |
|------------------------|---------|---------|---------|
| Search bar             | ✅      | ❌      | ❌      |
| Status filter chips    | ✅ (5)  | ❌      | ❌      |
| Type toggle chips      | ❌      | ❌      | ✅ (2)  |
| Row navigation (onTap) | ✅      | ❌      | ❌      |
| Row highlighting       | ✅ (overdue) | ❌ | ❌ |
| Checkbox column        | ✅      | ❌      | ❌      |
| Date formatting util   | ✅      | ✅      | ✅      |
| Status parsing util    | ✅      | ✅      | ❌      |

---

## Duplication Summary

### High-Certainty Duplication (verbatim or near-verbatim)

1. **Date formatter helper** - 3/3 screens (identical implementation)
2. **Layout structure** - 3/3 screens (Column → Row → Expanded → AppTable)
3. **Header row** - 3/3 screens (title + spacer + button)
4. **Loading/empty/table conditional** - 3/3 screens
5. **AppTable columns/rows pattern** - 3/3 screens

### Pattern Duplication (same structure, different data)

1. **Status/Type filter chips** - 2/3 screens (Invoice + Payment)
2. **Status badge rendering** - 3/3 screens (different status mappings)
3. **Cell styling conventions** - 3/3 screens:
   - Date: `AppTypography.bodySmall`
   - Primary text: `AppTypography.bodyMedium`
   - Amounts: `AppAmountText` with `AppTypography.amountTiny`

### Missing Reuse Opportunities

1. **No shared date formatter** - each screen reimplements
2. **No shared filter chip builder** - repetitive chip definitions
3. **No shared "build header row"** - each screen writes full Column structure
4. **No column presets** - common columns (Date, Amount, Status) defined fresh each time
5. **No status parsing utility** - Invoice + Expense both implement, Payment doesn't need it

---

## AppTable Current Capabilities

From `app_table.dart`:

**Available:**
- Fixed column widths
- Checkbox column (leftmost)
- Row tap handler
- Custom row background color
- Custom row border color
- Sortable headers (interface exists, not used)

**Missing (required by P1.3):**
- ❌ Sticky header
- ❌ Sticky totals row
- ❌ Dense mode toggle
- ❌ Column chooser
- ❌ Saved filters
- ❌ Export to CSV/Excel
- ❌ Keyboard navigation (J/K, Enter, R)
- ❌ Horizontal scroll for overflow columns

---

## Recommendations for P1.3

### 1. Extract Common Utilities
```dart
// lib/features/common/table/date_formatter.dart
String formatTableDate(String date);

// lib/features/common/table/status_parser.dart
InvoiceStatus parseStatus(String status, String context);
```

### 2. Create Table Configuration Presets
```dart
// Common column sets
TableColumns.dateAmountStatus()
TableColumns.invoice()
TableColumns.expense()
TableColumns.payment()
```

### 3. Create List Screen Scaffold Widget
```dart
class AppListScreen extends StatelessWidget {
  final String title;
  final Widget? filters;
  final Widget table;
  final VoidCallback? onAdd;
  // ... params for loading/empty states
  
  Widget build(...) => Column(
    // standardized layout
  );
}
```

### 4. Enhance AppTable (P1.3 core work)
Add to `TableColumn`:
```dart
class TableColumn {
  // existing fields...
  final bool isSticky;
  final String? field; // for sorting/export
}
```

Add to `AppTable`:
```dart
class AppTable {
  // existing fields...
  final bool stickyHeader;
  final Widget? footerRow;
  final bool denseMode;
  final List<String> hiddenColumns;
  final Function(String format)? onExport;
}
```

---

## Files for P1.3 Implementation

**Core enhancements needed:**
1. `flutter_client/lib/design_system/components/app_table.dart` - Add sticky, dense, column chooser
2. `flutter_client/lib/features/common/table/` - New utilities folder
3. Three list screens - refactor to use shared utilities once built

**Priority order:**
1. AppTable sticky header + footer (highest impact: Invoice, Ledger, Outstanding)
2. Dense mode toggle
3. Column chooser
4. Shared utilities (date formatter, status parser)
5. Keyboard navigation
6. Export functionality
7. Saved filters