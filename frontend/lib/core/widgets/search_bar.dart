/// Shared search bar widget with consistent ApexBooks styling.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../design_system/index.dart';

/// Debounced search bar with consistent ApexBooks styling.
/// Replaces ad-hoc search bars across feature screens.
class ApexSearchBar extends StatefulWidget {
  const ApexSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search…',
    this.debounceMs = 300,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final int debounceMs;

  @override
  State<ApexSearchBar> createState() => _ApexSearchBarState();
}

class _ApexSearchBarState extends State<ApexSearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      Duration(milliseconds: widget.debounceMs),
      () => widget.onChanged?.call(v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return TextField(
      controller: widget.controller,
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
        suffixIcon: widget.controller.text.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.clear_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                },
              )
            : null,
        filled: true,
        fillColor: colors.surfaceMuted,
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.md),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.md),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.md),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
    );
  }
}
