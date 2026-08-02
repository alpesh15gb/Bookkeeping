import 'dart:async';

import 'package:flutter/material.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/theme/app_colors.dart';

/// Debounced search bar driven by an [ApexTableController].
class InvoiceSearchBar extends StatefulWidget {
  const InvoiceSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'Search invoices by number or client…',
  });
  final ApexTableController controller;
  final String hintText;

  @override
  State<InvoiceSearchBar> createState() => _InvoiceSearchBarState();
}

class _InvoiceSearchBarState extends State<InvoiceSearchBar> {
  late final TextEditingController _ctrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.controller.value.search);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  static const _debounceMs = 300;

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: _debounceMs),
      () => widget.controller.setSearch(v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return TextField(
      controller: _ctrl,
      onChanged: _onChanged,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: colors.textMuted,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        suffixIcon: _ctrl.text.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.clear_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
                onPressed: () {
                  _ctrl.clear();
                  widget.controller.setSearch('');
                },
              )
            : null,
        filled: true,
        fillColor: colors.surfaceMuted,
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius_md),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius_md),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius_md),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
    );
  }
}
