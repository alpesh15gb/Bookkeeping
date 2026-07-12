/// Reusable party/entity selector widgets. Each one is a searchable bottom sheet
/// that fetches options from the API and returns the selected entity.
///
/// - [PartySelector] — customer / supplier
/// - [ProductSelector]
/// - [LedgerSelector]
/// - [BankAccountSelector]
/// - [WarehouseSelector]
/// - [TaxTemplateSelector]
/// - [PaymentTermsSelector]
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Generic reusable searchable bottom sheet
// ---------------------------------------------------------------------------

/// Generic selectable item with a display label and optional subtitle.
class SelectableItem<T> {
  const SelectableItem({
    required this.value,
    required this.label,
    this.subtitle,
  });
  final T value;
  final String label;
  final String? subtitle;
}

/// Shows a searchable bottom sheet of items. Returns the selected [SelectableItem]
/// or `null` if dismissed.
Future<T?> showEntitySelector<T>(
  BuildContext context, {
  required String title,
  required List<SelectableItem<T>> items,
  String Function(SelectableItem<T>)? displayLabel,
  T? initialValue,
}) async {
  final selected = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _EntitySelectorSheet<T>(
      title: title,
      items: items,
      initialValue: initialValue,
    ),
  );
  return selected;
}

class _EntitySelectorSheet<T> extends StatefulWidget {
  const _EntitySelectorSheet({
    required this.title,
    required this.items,
    this.initialValue,
  });

  final String title;
  final List<SelectableItem<T>> items;
  final T? initialValue;

  @override
  State<_EntitySelectorSheet<T>> createState() =>
      _EntitySelectorSheetState<T>();
}

class _EntitySelectorSheetState<T> extends State<_EntitySelectorSheet<T>> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
              .where(
                (i) => i.label.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search\u2026',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ApexRadius.md),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No results',
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(filtered[i].label),
                        subtitle: filtered[i].subtitle != null
                            ? Text(
                                filtered[i].subtitle!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textMuted,
                                ),
                              )
                            : null,
                        trailing: filtered[i].value == widget.initialValue
                            ? Icon(Icons.check, color: colors.primary)
                            : null,
                        onTap: () => Navigator.pop(context, filtered[i].value),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Convenience builder functions (expand as modules are added)
// ---------------------------------------------------------------------------

/// Build a [SelectableItem] list from any typed list with a label function.
List<SelectableItem<T>> buildSelectableItems<T>(
  List<T> items,
  String Function(T) labelOf, {
  String Function(T)? subtitleOf,
}) => items
    .map(
      (e) => SelectableItem<T>(
        value: e,
        label: labelOf(e),
        subtitle: subtitleOf?.call(e),
      ),
    )
    .toList();
