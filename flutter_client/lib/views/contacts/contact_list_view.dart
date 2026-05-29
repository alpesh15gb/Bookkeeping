import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/views/contacts/contact_form_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class ContactListView extends StatefulWidget {
  const ContactListView({super.key});

  @override
  State<ContactListView> createState() => _ContactListViewState();
}

class _ContactListViewState extends State<ContactListView> {
  final _searchCtrl = TextEditingController();
  String _typeFilter = 'ALL';

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

          // List
          Expanded(
            child: provider.isLoading && provider.contacts.isEmpty
                ? const LoadingState(message: 'Loading parties...')
                : provider.errorMessage != null && provider.contacts.isEmpty
                    ? ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchContacts())
                    : filtered.isEmpty
                        ? EmptyState(
                            icon: Icons.people_outlined,
                            title: _searchCtrl.text.isNotEmpty || _typeFilter != 'ALL'
                                ? 'No parties match your search'
                                : 'No parties yet',
                            subtitle: _searchCtrl.text.isNotEmpty || _typeFilter != 'ALL'
                                ? 'Try clearing the filters'
                                : 'Add your first customer or vendor',
                            actionLabel: 'Add Party',
                            onAction: () => _showForm(),
                          )
                        : ListView.separated(
                            padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
                            itemCount: filtered.length,
                            separatorBuilder: (context, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final contact = filtered[i];
                              return AppCard(
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
                                          onPressed: () async {
                                            final confirm = await AppConfirmDialog.show(
                                              context,
                                              title: 'Delete Party?',
                                              message: 'Are you sure you want to delete ${contact.name}?',
                                            );
                                            if (confirm == true) {
                                              final success = await provider.deleteContact(contact.id);
                                              if (!success && mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(provider.errorMessage ?? 'Delete failed'),
                                                    backgroundColor: AppColors.error,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          icon: const Icon(Icons.delete_outlined, size: 14),
                                          label: const Text('Delete'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.error,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            textStyle: AppTextStyles.buttonSmall,
                                            side: BorderSide(color: AppColors.error.withOpacity(0.3)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
