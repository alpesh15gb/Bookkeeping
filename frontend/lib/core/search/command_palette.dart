/// Command palette — opens on Ctrl+K / Cmd+K and lets the user quickly search
/// and navigate to any module, shortcut, or registered feature.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/masters/contacts/presentation/contact_form_screen.dart';
import '../../features/masters/products/presentation/product_form_screen.dart';
import '../../features/sales/presentation/invoice_form_screen.dart';
import '../config/feature_flags.dart';
import '../theme/app_colors.dart';

/// A modal overlay that captures keyboard input and displays a searchable list
/// of commands + global search results. Call [CommandPalette.show] to open.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  /// Opens the command palette as a full-screen overlay.
  static void show(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      barrierDismissible: true,
      barrierColor: Colors.black45,
      builder: (_) => const _CommandPaletteDialog(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  // Built-in quick commands.
  static const _commands = [
    _Command('New Invoice', 'sales/invoices/create', Icons.add_circle_outline),
    _Command('New Bill', 'purchases/bills/create', Icons.add_circle_outline),
    _Command(
      'New Customer',
      'masters/customers/create',
      Icons.person_add_outlined,
    ),
    _Command(
      'New Product',
      'masters/products/create',
      Icons.inventory_2_outlined,
    ),
    _Command(
      'New Payment',
      'banking/payments/create',
      Icons.account_balance_outlined,
    ),
    _Command('Reports', 'reports', Icons.analytics_outlined),
    _Command('Settings', 'company/settings', Icons.settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _controller.addListener(() => setState(() => _query = _controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final filtered = _query.isEmpty
        ? _commands
        : _commands
              .where(
                (c) => c.label.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
          child: Card(
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: 'Search commands and modules\u2026',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (v) {
                      if (filtered.isNotEmpty)
                        _navigateTo(filtered.first.route);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _query.isEmpty
                                ? 'Type to search\u2026'
                                : 'No results',
                            style: TextStyle(color: colors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => ListTile(
                            leading: Icon(filtered[i].icon, size: 20),
                            title: Text(filtered[i].label),
                            subtitle: Text(
                              filtered[i].route,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textMuted,
                              ),
                            ),
                            onTap: () => _navigateTo(filtered[i].route),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateTo(String route) {
    Navigator.of(context).pop(); // close the palette
    // Use the navigation pattern established across the app:
    // form screens are pushed via Navigator.push(MaterialPageRoute(...))
    // (see dashboard_screen.dart lines 70-72, invoice_list_screen.dart line 39).
    switch (route) {
      case 'sales/invoices/create':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const InvoiceFormScreen()));
        break;
      case 'masters/customers/create':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ContactFormScreen()));
        break;
      case 'masters/products/create':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ProductFormScreen()));
        break;
      // 'purchases/bills/create', 'banking/payments/create',
      // 'reports', and 'company/settings' don't have dedicated
      // screens yet — the palette simply closes.
    }
  }
}

class _CommandPaletteDialog extends ConsumerStatefulWidget {
  const _CommandPaletteDialog();
  @override
  ConsumerState<_CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends ConsumerState<_CommandPaletteDialog> {
  @override
  Widget build(BuildContext context) {
    if (!isEnabled(ref, FeatureFlags.commandPalette)) {
      return const SizedBox.shrink();
    }
    return const CommandPalette();
  }
}

@immutable
class _Command {
  const _Command(this.label, this.route, this.icon);
  final String label;
  final String route;
  final IconData icon;
}

/// Helper widget that captures Ctrl+K / Cmd+K and opens the palette.
class CommandPaletteShortcut extends StatefulWidget {
  const CommandPaletteShortcut({super.key, required this.child});
  final Widget child;
  @override
  State<CommandPaletteShortcut> createState() => _CommandPaletteShortcutState();
}

class _CommandPaletteShortcutState extends State<CommandPaletteShortcut> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // A single key event carries exactly one logical key, so the modifier and
    // the letter can never be equal on the same event. Read the modifier state
    // from the hardware keyboard and match the letter on this event.
    final isK = event.logicalKey == LogicalKeyboardKey.keyK;
    final hasModifier =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isK && hasModifier) {
      CommandPalette.show(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
