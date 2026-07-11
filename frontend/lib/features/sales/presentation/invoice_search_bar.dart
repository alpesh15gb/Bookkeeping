import 'dart:async';

import 'package:flutter/material.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/constants/app_constants.dart';

/// Debounced search bar driven by an [ApexTableController].
class InvoiceSearchBar extends StatefulWidget {
  const InvoiceSearchBar({super.key, required this.controller});
  final ApexTableController controller;

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

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () => widget.controller.setSearch(v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: _onChanged,
      decoration: InputDecoration(
        hintText: 'Search invoices by number or client\u2026',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        suffixIcon: _ctrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () {
                  _ctrl.clear();
                  widget.controller.setSearch('');
                },
              )
            : null,
      ),
    );
  }
}
