import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/views/contacts/contact_form_view.dart';
import 'package:flutter_client/views/reports/party_statement_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
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

    final totalCount = filtered.length;
    final customerCount = filtered.where((c) => c.contactType == 'CUSTOMER' || c.contactType == 'BOTH').length;
    final vendorCount = filtered.where((c) => c.contactType == 'VENDOR' || c.contactType == 'BOTH').length;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showForm(),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          // ── Search + Filter bar ──────────────────────────────
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 8,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search parties...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 16),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 14),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.borderInput,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.borderInput,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        child: ElevatedButton.icon(
                          onPressed: () => _showForm(),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Party'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            textStyle: AppTextStyles.buttonSmall,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChipWithCount(
                        label: 'All', count: totalCount,
                        isSelected: _typeFilter == 'ALL',
                        onTap: () => setState(() => _typeFilter = 'ALL'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Customer', count: customerCount,
                        isSelected: _typeFilter == 'CUSTOMER',
                        onTap: () => setState(() => _typeFilter = 'CUSTOMER'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Vendor', count: vendorCount,
                        isSelected: _typeFilter == 'VENDOR',
                        onTap: () => setState(() => _typeFilter = 'VENDOR'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── List ─────────────────────────────────────────────
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
                                EmptyState(
                                  icon: Icons.people_outlined,
                                  title: _searchCtrl.text.isNotEmpty ||
                                          _typeFilter != 'ALL'
                                      ? 'No parties match your search'
                                      : 'No parties yet',
                                  subtitle: _searchCtrl.text.isNotEmpty ||
                                          _typeFilter != 'ALL'
                                      ? 'Try clearing the filters'
                                      : 'Add your first customer or vendor',
                                  actionLabel: 'Add Party',
                                  onAction: () => _showForm(),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async => provider.fetchContacts(),
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                isMobile ? 12 : 20,
                                8,
                                isMobile ? 12 : 20,
                                isMobile ? 80 : 20,
                              ),
                              itemCount: filtered.length,
                              separatorBuilder: (context, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, i) {
                                final contact = filtered[i];
                                return _buildSwipeableContact(
                                  contact,
                                  _CompactContactCard(
                                    contact: contact,
                                    onEdit: () =>
                                        _showForm(contact: contact),
                                    onDelete: () =>
                                        _deleteSingleContact(contact),
                                    onStatement: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              PartyStatementView(
                                                initialContact: contact,
                                          ),
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
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: name + type badge + icon actions
          Row(
            children: [
              Expanded(
                child: Text(
                  contact.name,
                  style: AppTextStyles.h3.copyWith(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              StatusBadge.fromContactType(contact.contactType),
              const SizedBox(width: 4),
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
          ),

          // Row 2: phone + GSTIN on a single line
          if (contact.phone != null || contact.gstin != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (contact.phone != null) ...[
                  Icon(Icons.phone_outlined,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(contact.phone!,
                      style: AppTextStyles.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ],
                if (contact.phone != null &&
                    contact.gstin != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6),
                    child: Container(
                      width: 1,
                      height: 10,
                      color: AppColors.borderInput,
                    ),
                  ),
                if (contact.gstin != null) ...[
                  Icon(Icons.pin_outlined,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(contact.gstin!,
                      style: AppTextStyles.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
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
