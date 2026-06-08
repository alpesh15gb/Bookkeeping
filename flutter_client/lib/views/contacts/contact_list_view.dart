import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/views/contacts/contact_form_view.dart';
import 'package:flutter_client/views/reports/party_statement_view.dart';
import 'package:flutter_client/views/shared/app_components.dart' show StatusBadge, ErrorState, FilterChipWithCount, AppConfirmDialog, HeroSummaryCard;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactListView extends StatefulWidget {
  const ContactListView({super.key});

  @override
  State<ContactListView> createState() => _ContactListViewState();
}

class _ContactListViewState extends State<ContactListView> {
  final _searchCtrl = TextEditingController();
  String _typeFilter = 'ALL';
  double _swipeProgress = 0.0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<ContactProvider>().fetchContacts());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ContactModel> _filtered(List<ContactModel> contacts) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return contacts.where((c) {
      final matchesSearch = q.isEmpty ||
          c.name.toLowerCase().contains(q) ||
          (c.phone?.contains(q) ?? false) ||
          (c.gstin?.toLowerCase().contains(q) ?? false) ||
          (c.email?.toLowerCase().contains(q) ?? false);
      final matchesType = _typeFilter == 'ALL' ||
          c.contactType == _typeFilter ||
          (c.contactType == 'BOTH');
      return matchesSearch && matchesType;
    }).toList();
  }

  void _showForm({ContactModel? contact}) {
    showDialog(
      context: context,
      builder: (context) => ContactFormView(contact: contact),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);
    final filtered = _filtered(provider.contacts);

    final totalCount = provider.contacts.length;
    final customerCount = provider.contacts.where((c) => c.contactType == 'CUSTOMER' || c.contactType == 'BOTH').length;
    final vendorCount = provider.contacts.where((c) => c.contactType == 'VENDOR' || c.contactType == 'BOTH').length;

    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showForm(),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: AppInput(
                controller: _searchCtrl,
                hint: 'Search parties...',
                prefix: const Icon(Icons.search_rounded, size: 16),
                suffix: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            AppStatusTabBar(
              tabs: const ['ALL', 'CUSTOMER', 'VENDOR'],
              activeTab: _typeFilter,
              onTabChanged: (tab) {
                setState(() => _typeFilter = tab);
              },
              badges: {
                'ALL': totalCount,
                'CUSTOMER': customerCount,
                'VENDOR': vendorCount,
              },
            ),
            if (provider.contacts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: HeroSummaryCard(
                  title: 'Total Parties',
                  amount: filtered.length,
                  subtitle: '${filtered.where((c) => c.contactType == 'CUSTOMER' || c.contactType == 'BOTH').length} customers · ${filtered.where((c) => c.contactType == 'VENDOR' || c.contactType == 'BOTH').length} vendors',
                  icon: Icons.people_outlined,
                  formatAsCurrency: false,
                ),
              ),
            Expanded(
              child: provider.isLoading && provider.contacts.isEmpty
                  ? const ListSkeleton()
                  : provider.errorMessage != null && provider.contacts.isEmpty
                      ? ErrorState(
                          message: provider.errorMessage!,
                          onRetry: () => provider.fetchContacts(),
                        )
                      : filtered.isEmpty
                          ? RefreshIndicator(
                              onRefresh: () async => provider.fetchContacts(),
                              child: ListView(
                                children: [
                                  const SizedBox(height: 120),
                                  AppEmptyState(
                                    icon: Icons.people_outlined,
                                    title: 'No parties match your search',
                                    subtitle: 'Try clearing the filters or add a party',
                                    actionLabel: 'Add Party',
                                    onAction: () => _showForm(),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () async => provider.fetchContacts(),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: filtered.length,
                                separatorBuilder: (context, _) => const SizedBox(height: 6),
                                itemBuilder: (context, i) {
                                  final contact = filtered[i];
                                  return _buildSwipeableContact(
                                    contact,
                                    _CompactContactCard(
                                      contact: contact,
                                      onEdit: () => _showForm(contact: contact),
                                      onDelete: () => _deleteSingleContact(contact),
                                      onStatement: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PartyStatementView(initialContact: contact),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          AppCommandBar(
            title: 'Parties & Contacts',
            searchWidget: AppInput(
              controller: _searchCtrl,
              hint: 'Search by name, phone, GSTIN...',
              prefix: const Icon(Icons.search_rounded, size: 16),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              AppButton(
                label: 'Add Party',
                icon: Icons.add,
                isPrimary: true,
                onTap: () => _showForm(),
              ),
            ],
          ),
          AppStatusTabBar(
            tabs: const ['ALL', 'CUSTOMER', 'VENDOR'],
            activeTab: _typeFilter,
            onTabChanged: (tab) {
              setState(() => _typeFilter = tab);
            },
            badges: {
              'ALL': totalCount,
              'CUSTOMER': customerCount,
              'VENDOR': vendorCount,
            },
          ),
          Expanded(
            child: provider.isLoading && provider.contacts.isEmpty
                ? const ListSkeleton()
                : provider.errorMessage != null && provider.contacts.isEmpty
                    ? ErrorState(
                        message: provider.errorMessage!,
                        onRetry: () => provider.fetchContacts(),
                      )
                    : filtered.isEmpty
                        ? AppEmptyState(
                            icon: Icons.people_outlined,
                            title: 'No parties found',
                            subtitle: 'Add your first customer or vendor to get started',
                            actionLabel: 'Add Party',
                            onAction: () => _showForm(),
                          )
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: const BoxDecoration(
                                  color: AppColors.bgSurface,
                                  border: Border(bottom: BorderSide(color: AppColors.border)),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 4, child: Text('PARTY NAME', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 3, child: Text('CONTACT DETAILS', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 3, child: Text('GSTIN / PAN', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 2, child: Text('STATE', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                    Expanded(flex: 2, child: Text('TYPE', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                    SizedBox(width: 120, child: Text('ACTIONS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                                  itemBuilder: (context, index) {
                                    final contact = filtered[index];
                                    final details = [
                                      if (contact.phone != null && contact.phone!.isNotEmpty) contact.phone,
                                      if (contact.email != null && contact.email!.isNotEmpty) contact.email,
                                    ].join(' | ');

                                    return InkWell(
                                      onTap: () => _showForm(contact: contact),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 4,
                                              child: Row(
                                                children: [
                                                  AppAvatar(name: contact.name, size: 28),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      contact.name,
                                                      style: AppTextStyles.bodyMedium.copyWith(
                                                        color: AppColors.brandNavy,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                details.isNotEmpty ? details : 'No contact details',
                                                style: AppTextStyles.bodySmall,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                [
                                                  if (contact.gstin != null && contact.gstin!.isNotEmpty) contact.gstin,
                                                  if (contact.pan != null && contact.pan!.isNotEmpty) contact.pan,
                                                ].join(' / ').toUpperCase(),
                                                style: AppTextStyles.bodySmall.copyWith(
                                                  fontFamily: 'Courier',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                contact.stateCode,
                                                style: AppTextStyles.bodySmall,
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Center(
                                                child: Text(
                                                  contact.contactType,
                                                  style: AppTextStyles.overline.copyWith(
                                                    color: contact.contactType == 'CUSTOMER'
                                                        ? AppColors.accentBlue
                                                        : contact.contactType == 'VENDOR'
                                                            ? AppColors.goldAccent
                                                            : AppColors.success,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: AppRowActions(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                                                    onPressed: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) => PartyStatementView(initialContact: contact),
                                                        ),
                                                      );
                                                    },
                                                    tooltip: 'Statement',
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_outlined, size: 16),
                                                    onPressed: () => _showForm(contact: contact),
                                                    tooltip: 'Edit',
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline, size: 16),
                                                    color: AppColors.error,
                                                    onPressed: () => _deleteSingleContact(contact),
                                                    tooltip: 'Delete',
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeableContact(ContactModel contact, Widget child) {
    return Dismissible(
      key: Key('contact_dismiss_${contact.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.green[700],
        child: const Row(
          children: [
            Icon(Icons.phone, color: Colors.white),
            SizedBox(width: 8),
            Text('Call / WhatsApp',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: _swipeProgress > 0.70 ? AppColors.error : AppColors.info,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              _swipeProgress > 0.70 ? 'Delete Party' : 'Statement',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Icon(
              _swipeProgress > 0.70 ? Icons.delete : Icons.receipt_long,
              color: Colors.white,
            ),
          ],
        ),
      ),
      onUpdate: (details) {
        setState(() {
          _swipeProgress = details.progress;
        });
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (contact.phone != null && contact.phone!.isNotEmpty) {
            _showContactActionSheet(contact);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('No phone number available for this contact'),
              ),
            );
          }
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (_swipeProgress > 0.70) {
            final confirm = await AppConfirmDialog.show(
              context,
              title: 'Delete Party?',
              message:
                  'Are you sure you want to delete ${contact.name}? This action can be undone.',
            );
            if (confirm == true) {
              _deleteSingleContact(contact);
              return true;
            }
            return false;
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PartyStatementView(initialContact: contact),
              ),
            );
            return false;
          }
        }
        return false;
      },
      child: child,
    );
  }

  void _showContactActionSheet(ContactModel contact) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Contact ${contact.name}',
                  style: AppTextStyles.h3,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.phone,
                    color: AppColors.brandNavy),
                title: const Text('Call'),
                subtitle: Text(contact.phone!),
                onTap: () {
                  Navigator.pop(context);
                  HapticHelper.light();
                  _makeCall(contact.phone!);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline,
                    color: Colors.green),
                title: const Text('WhatsApp'),
                subtitle: Text(contact.phone!),
                onTap: () {
                  Navigator.pop(context);
                  HapticHelper.light();
                  _openWhatsApp(contact.phone!);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _makeCall(String phone) async {
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _deleteSingleContact(ContactModel contact) async {
    final provider = context.read<ContactProvider>();
    final success = await provider.deleteContact(contact.id);
    if (success) {
      HapticHelper.delete();
      provider.fetchContacts();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: AppColors.brandNavy,
          content: Text('Party ${contact.name} deleted'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.goldAccent,
            onPressed: () async {
              final payload = contact.toJson();
              payload.remove('id');
              final ok = await provider.addContact(contact);
              if (ok) {
                HapticHelper.success();
                provider.fetchContacts();
              }
            },
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(provider.errorMessage ?? 'Delete failed'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Compact contact card
// ═══════════════════════════════════════════════════════════════════

class _CompactContactCard extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onStatement;

  const _CompactContactCard({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
    required this.onStatement,
  });

  @override
  Widget build(BuildContext context) {
    String subtitle = '';
    if (contact.phone != null && contact.phone!.isNotEmpty) {
      subtitle = contact.phone!;
    }
    if (contact.gstin != null && contact.gstin!.isNotEmpty) {
      if (subtitle.isNotEmpty) subtitle += ' | ';
      subtitle += contact.gstin!;
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListTile(
        leadingText: _initials(contact.name),
        title: contact.name,
        subtitle: subtitle.isNotEmpty ? subtitle : null,
        badge: StatusBadge.fromContactType(contact.contactType),
        hoverActions: [
          _iconBtn(
            icon: Icons.receipt_long_outlined,
            tooltip: 'Statement',
            color: AppColors.brandNavy,
            onTap: onStatement,
          ),
          _iconBtn(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onTap: onEdit,
          ),
          _iconBtn(
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            color: AppColors.error,
            onTap: onDelete,
          ),
        ],
        onTap: onEdit,
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '';
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }
}
