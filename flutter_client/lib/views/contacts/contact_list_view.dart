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

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Search + Filter bar
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 10,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search parties by name, phone, GSTIN...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.borderInput),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.borderInput),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['ALL', 'CUSTOMER', 'VENDOR', 'BOTH'].map((t) {
                      final isSelected = _typeFilter == t;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            t == 'ALL' ? 'All' : t,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _typeFilter = t),
                          selectedColor: AppColors.brandNavy,
                          backgroundColor: AppColors.borderLight,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: provider.isLoading && provider.contacts.isEmpty
                ? const ListSkeleton()
                : provider.errorMessage != null && provider.contacts.isEmpty
                    ? ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchContacts())
                    : filtered.isEmpty
                        ? RefreshIndicator(
                            onRefresh: () async => provider.fetchContacts(),
                            child: ListView(
                              children: [
                                const SizedBox(height: 120),
                                EmptyState(
                                  icon: Icons.people_outlined,
                                  title: _searchCtrl.text.isNotEmpty || _typeFilter != 'ALL'
                                      ? 'No parties match your search'
                                      : 'No parties yet',
                                  subtitle: _searchCtrl.text.isNotEmpty || _typeFilter != 'ALL'
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
                                padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
                                itemCount: filtered.length,
                                separatorBuilder: (context, _) => const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final contact = filtered[i];
                                  return _buildSwipeableContact(
                                    contact,
                                    AppCard(
                                      child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(contact.name, style: AppTextStyles.h3),
                                            ),
                                            StatusBadge.fromContactType(contact.contactType),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            if (contact.phone != null) ...[
                                              Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
                                              const SizedBox(width: 6),
                                              Text(contact.phone!, style: AppTextStyles.bodySmall),
                                              const SizedBox(width: 16),
                                            ],
                                            if (contact.gstin != null) ...[
                                              Icon(Icons.pin_outlined, size: 14, color: AppColors.textMuted),
                                              const SizedBox(width: 6),
                                              Text(contact.gstin!, style: AppTextStyles.bodySmall),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => const PartyStatementView(),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.receipt_long_outlined, size: 14),
                                              label: const Text('Statement'),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                textStyle: AppTextStyles.buttonSmall,
                                                side: const BorderSide(color: AppColors.brandNavy),
                                                foregroundColor: AppColors.brandNavy,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            OutlinedButton.icon(
                                              onPressed: () => _showForm(contact: contact),
                                              icon: const Icon(Icons.edit_outlined, size: 14),
                                              label: const Text('Edit'),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                textStyle: AppTextStyles.buttonSmall,
                                                side: const BorderSide(color: AppColors.borderInput),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            OutlinedButton.icon(
                                              onPressed: () => _deleteSingleContact(contact),
                                              icon: const Icon(Icons.delete_outlined, size: 14),
                                              label: const Text('Delete'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.error,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                textStyle: AppTextStyles.buttonSmall,
                                                side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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
            Text('Call / WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Icon(_swipeProgress > 0.70 ? Icons.delete : Icons.receipt_long, color: Colors.white),
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
              const SnackBar(content: Text('No phone number available for this contact')),
            );
          }
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (_swipeProgress > 0.70) {
            final confirm = await AppConfirmDialog.show(
              context,
              title: 'Delete Party?',
              message: 'Are you sure you want to delete ${contact.name}? This action can be undone.',
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
                builder: (_) => PartyStatementView(initialContact: contact),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Contact ${contact.name}', style: AppTextStyles.h3),
              ),
              ListTile(
                leading: const Icon(Icons.phone, color: AppColors.brandNavy),
                title: const Text('Call'),
                subtitle: Text(contact.phone!),
                onTap: () {
                  Navigator.pop(context);
                  HapticHelper.light();
                  _makeCall(contact.phone!);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.green),
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
          content: Text(provider.errorMessage ?? 'Delete failed'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
