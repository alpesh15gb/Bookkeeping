import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/models/product.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ContactSearchSheet — searchable contact picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class ContactSearchSheet extends StatefulWidget {
  final List<ContactModel> contacts;
  final String title;
  final String placeholder;
  final String createLabel;
  final Function(String) onCreateNew;

  const ContactSearchSheet({
    super.key,
    required this.contacts,
    this.title = 'Select Customer',
    this.placeholder = 'Search name, phone, GSTIN...',
    this.createLabel = 'Add as new customer',
    required this.onCreateNew,
  });

  @override
  State<ContactSearchSheet> createState() => _ContactSearchSheetState();
}

class _ContactSearchSheetState extends State<ContactSearchSheet> {
  final _ctrl = TextEditingController();
  List<ContactModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.contacts;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? widget.contacts
            : widget.contacts.where((c) =>
                c.name.toLowerCase().contains(q) ||
                (c.phone?.contains(q) ?? false) ||
                (c.gstin?.toLowerCase().contains(q) ?? false)).toList();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim();
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: AppTextStyles.h3),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: widget.placeholder,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: _ctrl.clear)
                          : null,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  if (query.isNotEmpty)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.brandNavy,
                        radius: 18,
                        child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 16),
                      ),
                      title: Text(
                        'Create "$query"',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.brandNavy, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(widget.createLabel, style: AppTextStyles.caption),
                      onTap: () => widget.onCreateNew(query),
                    ),
                  if (_filtered.isEmpty && query.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.people_outline, size: 40, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text('No contacts found', style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  ..._filtered.map((c) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.goldAccent.withOpacity(0.6),
                          radius: 18,
                          child: Text(
                            c.name[0].toUpperCase(),
                            style: const TextStyle(color: AppColors.brandNavy, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        title: Text(c.name, style: AppTextStyles.bodyMedium),
                        subtitle: Text(
                          [
                            if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
                            if (c.gstin != null && c.gstin!.isNotEmpty) 'GST: ${c.gstin!}',
                          ].join('  ·  '),
                          style: AppTextStyles.caption,
                        ),
                        onTap: () => Navigator.pop(context, c),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductSearchSheet — searchable product picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class ProductSearchSheet extends StatefulWidget {
  final List<ProductModel> products;
  final Function(String) onCreateNew;
  final bool isPurchase;

  const ProductSearchSheet({
    super.key,
    required this.products,
    required this.onCreateNew,
    this.isPurchase = false,
  });

  @override
  State<ProductSearchSheet> createState() => _ProductSearchSheetState();
}

class _ProductSearchSheetState extends State<ProductSearchSheet> {
  final _ctrl = TextEditingController();
  List<ProductModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? widget.products
            : widget.products.where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.hsnSac.contains(q) ||
                (p.sku?.toLowerCase().contains(q) ?? false)).toList();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim();
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Product / Service', style: AppTextStyles.h3),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by name, SKU, HSN code...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: _ctrl.clear)
                          : null,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  if (query.isNotEmpty)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2E7D32),
                        radius: 18,
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      ),
                      title: Text(
                        'Create "$query"',
                        style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text('Add as new product or service', style: AppTextStyles.caption),
                      onTap: () => widget.onCreateNew(query),
                    ),
                  if (_filtered.isEmpty && query.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text('No products found', style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  ..._filtered.map((p) {
                    final isService = p.productType == 'SERVICE';
                    final price = widget.isPurchase ? p.purchasePrice : p.salesPrice;
                    return ListTile(
                      leading: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: isService ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isService ? Icons.miscellaneous_services_rounded : Icons.inventory_2_rounded,
                          size: 18,
                          color: isService ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
                        ),
                      ),
                      title: Text(p.name, style: AppTextStyles.bodyMedium),
                      subtitle: Text(
                        '₹${price.toStringAsFixed(2)}  ·  GST ${p.gstRate.toStringAsFixed(0)}%'
                        '${p.hsnSac.isNotEmpty ? '  ·  ${p.hsnSac}' : ''}',
                        style: AppTextStyles.caption,
                      ),
                      trailing: !isService && p.currentStock > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${p.currentStock.toStringAsFixed(0)} in stock',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                              ),
                            )
                          : null,
                      onTap: () => Navigator.pop(context, p),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
