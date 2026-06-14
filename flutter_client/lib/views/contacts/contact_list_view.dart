import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/views/contacts/contact_form_view.dart';
import 'package:flutter_client/views/reports/party_statement_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:url_launcher/url_launcher.dart';

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
    ).then((_) => setState(() {}));
  }

  void _deleteSingleContact(ContactModel contact) async {
    final provider = context.read<ContactProvider>();
    final success = await provider.deleteContact(contact.id);
    if (success) {
      HapticHelper.delete();
      provider.fetchContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            backgroundColor: AppColors.brandNavy,
            content: Text('Party ${contact.name} deleted'),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: AppColors.goldAccent,
              onPressed: () async {
                final ok = await provider.addContact(contact);
                if (ok) {
                  HapticHelper.success();
                  provider.fetchContacts();
                }
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _makeCall(String phone) async {
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContactProvider>();
    final filtered = _filtered(provider.contacts);

    final totalCount = provider.contacts.length;
    final customerCount = provider.contacts.where((c) => c.contactType == 'CUSTOMER' || c.contactType == 'BOTH').length;
    final vendorCount = provider.contacts.where((c) => c.contactType == 'VENDOR' || c.contactType == 'BOTH').length;

    return DocumentListView(
      title: 'Parties & Contacts',
      detailBuilder: (ctx, item) => PartyStatementView(initialContact: null),
      items: filtered.map((contact) {
        return DocumentItemData(
          id: contact.id,
          docNumber: contact.contactType,
          partyName: contact.name,
          date: null,
          amount: 0,
          status: contact.contactType,
        );
      }).toList(),
      filterTabs: [
        FilterTab('ALL', totalCount),
        FilterTab('CUSTOMER', customerCount),
        FilterTab('VENDOR', vendorCount),
      ],
      activeFilter: _typeFilter,
      onFilterChanged: (tab) {
        setState(() => _typeFilter = tab);
      },
      summary: null,
      searchController: _searchCtrl,
      searchHint: 'Search by name, phone, GSTIN...',
      onSearchChanged: (_) => setState(() {}),
      onRefresh: () async => provider.fetchContacts(),
      isLoading: provider.isLoading && provider.contacts.isEmpty,
      emptyTitle: 'No parties found',
      emptySubtitle: _typeFilter != 'ALL' || _searchCtrl.text.isNotEmpty
          ? 'Try clearing your filters'
          : 'Add your first customer or vendor to get started',
      emptyIcon: Icons.people_outlined,
      itemBuilder: (context, item, index) {
        final contact = filtered[index];
        return _buildContactCard(contact);
      },
    );
  }

  Widget _buildContactCard(ContactModel contact) {
    final details = [
      if (contact.phone != null && contact.phone!.isNotEmpty) contact.phone,
      if (contact.email != null && contact.email!.isNotEmpty) contact.email,
    ].join(' | ');

    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListTile(
        leadingText: _initials(contact.name),
        title: contact.name,
        subtitle: details.isNotEmpty ? details : null,
        badge: StatusBadge.fromContactType(contact.contactType),
        hoverActions: [
          _iconBtn(
            icon: Icons.receipt_long_outlined,
            tooltip: 'Statement',
            color: AppColors.brandNavy,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PartyStatementView(initialContact: contact)),
            ),
          ),
          if (contact.phone != null && contact.phone!.isNotEmpty)
            _iconBtn(
              icon: Icons.phone_outlined,
              tooltip: 'Call',
              color: AppColors.success,
              onTap: () => _makeCall(contact.phone!),
            ),
          _iconBtn(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onTap: () => _showForm(contact: contact),
          ),
          _iconBtn(
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            color: AppColors.error,
            onTap: () => _deleteSingleContact(contact),
          ),
        ],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PartyStatementView(initialContact: contact)),
        ),
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
