import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/detail_inspector.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../data/models/contact.dart';
import 'contact_controller.dart';
import 'contact_form_screen.dart';

final contactTableControllerProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>(
      (ref) => ApexTableController(),
    );

class ContactListScreen extends ConsumerStatefulWidget {
  const ContactListScreen({super.key});
  @override
  ConsumerState<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends ConsumerState<ContactListScreen> {
  late final ApexTableController _tableCtrl;
  Contact? _selected;

  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(contactTableControllerProvider);
  }

  List<ApexColumn<Contact>> _buildColumns() {
    final fmt = ref.read(numberFormatterProvider);
    return [
      ApexColumn(
        id: 'name',
        label: 'Name',
        value: (c) => c.name,
        sortable: true,
        width: 200,
        cellBuilder: (ctx, c, _) {
          final colors = apexColors(ctx);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              if ((c.email ?? '').isNotEmpty)
                Text(
                  c.email!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
            ],
          );
        },
      ),
      ApexColumn(
        id: 'contact_type',
        label: 'Type',
        value: (c) => c.contactType.displayLabel,
        sortable: true,
        width: 95,
        cellBuilder: (ctx, c, _) => Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            label: c.contactType.displayLabel,
            tone: c.contactType == ContactType.customer
                ? StatusTone.info
                : c.contactType == ContactType.vendor
                ? StatusTone.warning
                : StatusTone.primary,
          ),
        ),
      ),
      ApexColumn(
        id: 'gstin',
        label: 'GSTIN',
        value: (c) => c.gstin ?? '—',
        width: 150,
      ),
      ApexColumn(
        id: 'phone',
        label: 'Phone',
        value: (c) => c.phone ?? '—',
        width: 120,
      ),
      ApexColumn(
        id: 'opening_balance',
        label: 'Balance',
        value: (c) => fmt.currency(c.openingBalance),
        sortable: true,
        alignment: Alignment.centerRight,
        width: 120,
        cellBuilder: (ctx, c, _) {
          final colors = apexColors(ctx);
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              fmt.currency(c.openingBalance),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          );
        },
      ),
      ApexColumn(
        id: 'is_active',
        label: 'Status',
        value: (c) => c.isActive ? 'Active' : 'Inactive',
        width: 90,
        cellBuilder: (ctx, c, _) => Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            label: c.isActive ? 'ACTIVE' : 'INACTIVE',
            tone: c.isActive ? StatusTone.success : StatusTone.neutral,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final fmt = ref.read(numberFormatterProvider);
    final listWidget = BaseListScreen<Contact>(
      title: 'Contacts',
      columns: _buildColumns(),
      provider: contactControllerProvider,
      tableCtrl: _tableCtrl,
      onCreate: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ContactFormScreen()))
          .then((_) => ref.invalidate(contactControllerProvider)),
      onRowTap: (c) => setState(() => _selected = c),
      searchHint: 'Search contacts…',
    );
    if (_selected == null) return listWidget;
    if (ResponsiveLayout.isMobile(context)) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selected = null);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_selected!.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 20),
                tooltip: 'Edit',
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ContactFormScreen(contact: _selected),
                      ),
                    )
                    .then((_) {
                      ref.invalidate(contactControllerProvider);
                      setState(() => _selected = null);
                    }),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: colors.danger,
                ),
                tooltip: 'Delete',
                onPressed: () async {
                  final ok = await ref
                      .read(contactControllerProvider.notifier)
                      .delete(_selected!, context);
                  if (!context.mounted) return;
                  if (ok) {
                    ref.invalidate(contactControllerProvider);
                    setState(() => _selected = null);
                    await Navigator.of(context).maybePop();
                  }
                },
              ),
            ],
          ),
          body: DetailInspector(
            title: _selected!.name,
            subtitle: 'Type: ${_selected!.contactType.displayLabel}',
            onClose: () => setState(() => _selected = null),
            rows: [
              DetailRow('Type', _selected!.contactType.displayLabel),
              DetailRow('Status', _selected!.isActive ? 'Active' : 'Inactive'),
              DetailRow('Phone', _selected!.phone),
              DetailRow('Email', _selected!.email),
              DetailRow('GSTIN', _selected!.gstin),
              DetailRow('Opening Bal', fmt.currency(_selected!.openingBalance)),
              DetailRow('Credit Bal', fmt.currency(_selected!.creditBalance)),
            ],
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Edit Contact'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ContactFormScreen(contact: _selected),
                      ),
                    )
                    .then((_) {
                      ref.invalidate(contactControllerProvider);
                      setState(() => _selected = null);
                    }),
              ),
              OutlinedButton.icon(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: colors.danger,
                ),
                label: Text('Delete', style: TextStyle(color: colors.danger)),
                onPressed: () async {
                  final ok = await ref
                      .read(contactControllerProvider.notifier)
                      .delete(_selected!, context);
                  if (ok) {
                    ref.invalidate(contactControllerProvider);
                    setState(() => _selected = null);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: listWidget),
        const VerticalDivider(width: 1),
        DetailInspector(
          title: _selected!.name,
          subtitle: 'Type: ${_selected!.contactType.displayLabel}',
          onClose: () => setState(() => _selected = null),
          rows: [
            DetailRow('Type', _selected!.contactType.displayLabel),
            DetailRow('Status', _selected!.isActive ? 'Active' : 'Inactive'),
            DetailRow('Phone', _selected!.phone),
            DetailRow('Email', _selected!.email),
            DetailRow('GSTIN', _selected!.gstin),
            DetailRow('Opening Bal', fmt.currency(_selected!.openingBalance)),
            DetailRow('Credit Bal', fmt.currency(_selected!.creditBalance)),
          ],
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit Contact'),
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => ContactFormScreen(contact: _selected),
                    ),
                  )
                  .then((_) {
                    ref.invalidate(contactControllerProvider);
                    setState(() => _selected = null);
                  }),
            ),
            OutlinedButton.icon(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: colors.danger,
              ),
              label: Text('Delete', style: TextStyle(color: colors.danger)),
              onPressed: () async {
                final ok = await ref
                    .read(contactControllerProvider.notifier)
                    .delete(_selected!, context);
                if (ok) {
                  ref.invalidate(contactControllerProvider);
                  setState(() => _selected = null);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
