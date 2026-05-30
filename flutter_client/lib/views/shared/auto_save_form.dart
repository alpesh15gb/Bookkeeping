import 'dart:async';
import 'package:flutter/material.dart';

class AutoSaveForm extends StatefulWidget {
  final Widget child;
  final Future<void> Function(Map<String, dynamic> data) onSave;
  final Duration debounceDuration;
  final bool enabled;

  const AutoSaveForm({
    super.key,
    required this.child,
    required this.onSave,
    this.debounceDuration = const Duration(seconds: 3),
    this.enabled = true,
  });

  @override
  State<AutoSaveForm> createState() => _AutoSaveFormState();
}

class _AutoSaveFormState extends State<AutoSaveForm> {
  Timer? _debounceTimer;
  bool _isDirty = false;

  void markDirty() {
    if (!widget.enabled) return;
    _isDirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, _autoSave);
  }

  Future<void> _autoSave() async {
    if (!_isDirty) return;
    _isDirty = false;
    try {
      await widget.onSave({});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Draft saved', style: TextStyle(fontSize: 12)),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.grey[700],
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
