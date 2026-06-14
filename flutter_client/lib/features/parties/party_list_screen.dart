import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/contact.dart';
import '../../../providers/contact_provider.dart';

class PartyListScreen extends StatefulWidget {
  const PartyListScreen({super.key});

  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  String? _selectedType;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().fetchContacts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactProvider = context.watch<ContactProvider>();
    final contacts = contactProvider.contacts;
    final isLoading = contactProvider.isLoading;

    final filteredContacts = _filterContacts(contacts);

    final allCount = contacts.length;
    final customerCount = contacts.where((c) => c.contactType == 'CUSTOMER' || c.contactType == 'BOTH').length;
    final vendorCount = contacts.where((c) => c.contactType == 'VENDOR' || c.contactType == 'BOTH').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Parties', style: AppTypography.headlineLarge),
            const Spacer(),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search parties...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.gray200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.gray200),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppButton(
              label: '+ Add Party',
              icon: Icons.person_add,
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        Row(
          children: [
            AppFilterChip(
              label: 'All',
              count: allCount,
              isSelected: _selectedType == null,
              onTap: () => setState(() => _selectedType = null),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Customers',
              count: customerCount,
              isSelected: _selectedType == 'CUSTOMER',
              onTap: () => setState(() => _selectedType = 'CUSTOMER'),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Vendors',
              count: vendorCount,
              isSelected: _selectedType == 'VENDOR',
              onTap: () => setState(() => _selectedType = 'VENDOR'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        Expanded(
          child: isLoading && contacts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filteredContacts.isEmpty
                  ? AppEmptyState(
                      icon: Icons.people_outline,
                      title: 'No parties found',
                      subtitle: _searchQuery.isNotEmpty ? 'Try a different search' : 'Add your first party',
                    )
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Party', width: 220),
                        TableColumn(label: 'Type', width: 110),
                        TableColumn(label: 'Phone', width: 140),
                        TableColumn(label: 'GSTIN', width: 160),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: filteredContacts.map((contact) {
                        return AppTableRow(
                          onTap: () => context.go('/parties/${contact.id}'),
                          cells: [
                            Text(contact.name, style: AppTypography.bodyMedium),
                            Text(_formatContactType(contact.contactType), style: AppTypography.bodySmall),
                            Text(contact.phone ?? '-', style: AppTypography.bodySmall),
                            Text(contact.gstin ?? '-', style: AppTypography.bodySmall),
                            AppStatusBadge(
                              status: contact.isActive ? InvoiceStatus.paid : InvoiceStatus.cancelled,
                            ),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }

  List<ContactModel> _filterContacts(List<ContactModel> contacts) {
    var result = contacts;

    if (_selectedType != null) {
      result = result.where((c) =>
        c.contactType == _selectedType || c.contactType == 'BOTH'
      ).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.phone?.contains(q) ?? false) ||
        (c.gstin?.toLowerCase().contains(q) ?? false) ||
        (c.email?.toLowerCase().contains(q) ?? false)
      ).toList();
    }

    return result;
  }

  String _formatContactType(String type) {
    switch (type) {
      case 'CUSTOMER': return 'Customer';
      case 'VENDOR': return 'Vendor';
      case 'BOTH': return 'Both';
      default: return type;
    }
  }
}
