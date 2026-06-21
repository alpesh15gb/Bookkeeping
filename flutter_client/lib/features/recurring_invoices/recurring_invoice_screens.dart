import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/recurring_invoice_provider.dart';
import '../../../providers/contact_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../models/recurring_invoice.dart';

String _formatAmount(dynamic amount) {
  final val = double.tryParse((amount ?? 0).toString()) ?? 0.0;
  return '₹${val.toStringAsFixed(0)}';
}

String _formatDate(String date) {
  if (date.isEmpty) return '-';
  try {
    final d = DateTime.parse(date);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  } catch (_) {
    return date;
  }
}

class RecurringInvoiceListScreen extends StatefulWidget {
  const RecurringInvoiceListScreen({super.key});
  @override
  State<RecurringInvoiceListScreen> createState() => _RecurringInvoiceListScreenState();
}

class _RecurringInvoiceListScreenState extends State<RecurringInvoiceListScreen> {
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecurringInvoiceProvider>().fetchRecurringInvoices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecurringInvoiceProvider>();
    final allItems = provider.items;
    final isLoading = provider.isLoading;

    List<RecurringInvoiceModel> filtered = allItems;
    if (_selectedFilter == 'Active') filtered = allItems.where((e) => e.isActive).toList();
    if (_selectedFilter == 'Paused') filtered = allItems.where((e) => !e.isActive).toList();

    final activeCount = allItems.where((e) => e.isActive).length;
    final pausedCount = allItems.where((e) => !e.isActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recurring Invoices', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(
              label: '+ Recurring Invoice',
              icon: Icons.add,
              onPressed: () => context.go('/recurring-invoices/create'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(
              label: 'All',
              count: allItems.length,
              isSelected: _selectedFilter == 'All',
              onTap: () => setState(() => _selectedFilter = 'All'),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Active',
              count: activeCount,
              isSelected: _selectedFilter == 'Active',
              onTap: () => setState(() => _selectedFilter = 'Active'),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Paused',
              count: pausedCount,
              isSelected: _selectedFilter == 'Paused',
              onTap: () => setState(() => _selectedFilter = 'Paused'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && allItems.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? AppEmptyState(
                      icon: Icons.repeat,
                      title: 'No Recurring Invoices',
                      subtitle: 'Set up templates to automatically generate invoices on a schedule',
                    )
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Template Name', width: 200),
                        TableColumn(label: 'Customer', width: 180),
                        TableColumn(label: 'Frequency', width: 150),
                        TableColumn(label: 'Next Date', width: 120),
                        TableColumn(label: 'Generated', width: 90),
                        TableColumn(label: 'Status', width: 100),
                        TableColumn(label: '', width: 50),
                      ],
                      rows: filtered.map((item) {
                        final contactName = item.contact?.name ?? item.contactName ?? '-';
                        return AppTableRow(
                          onTap: () => context.go('/recurring-invoices/${item.id}'),
                          cells: [
                            Text(item.templateName, style: AppTypography.labelLarge),
                            Text(contactName, style: AppTypography.bodyMedium),
                            Text(item.frequencyLabel, style: AppTypography.bodySmall),
                            Text(_formatDate(item.nextDate), style: AppTypography.bodySmall),
                            Text('${item.occurrencesCreated}', style: AppTypography.bodySmall),
                            AppStatusBadge(
                              status: item.isActive ? InvoiceStatus.paid : InvoiceStatus.cancelled,
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onPressed: () => _showActions(context, item),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }

  void _showActions(BuildContext context, RecurringInvoiceModel item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/recurring-invoices/${item.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Generate Invoice Now'),
              onTap: () async {
                Navigator.pop(ctx);
                final provider = context.read<RecurringInvoiceProvider>();
                final result = await provider.generateInvoice(item.id);
                if (result != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Invoice generated: ${result['invoice_number']}')),
                  );
                  provider.fetchRecurringInvoices();
                }
              },
            ),
            ListTile(
              leading: Icon(item.isActive ? Icons.pause : Icons.play_arrow),
              title: Text(item.isActive ? 'Pause' : 'Resume'),
              onTap: () async {
                Navigator.pop(ctx);
                final provider = context.read<RecurringInvoiceProvider>();
                await provider.updateRecurringInvoice(item.id, {'is_active': !item.isActive});
                provider.fetchRecurringInvoices();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final provider = context.read<RecurringInvoiceProvider>();
                await provider.deleteRecurringInvoice(item.id);
                provider.fetchRecurringInvoices();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class RecurringInvoiceFormScreen extends StatefulWidget {
  final String? id;

  const RecurringInvoiceFormScreen({super.key, this.id});

  bool get isEdit => id != null;

  @override
  State<RecurringInvoiceFormScreen> createState() => _RecurringInvoiceFormScreenState();
}

class _RecurringInvoiceFormScreenState extends State<RecurringInvoiceFormScreen> {
  final _templateNameController = TextEditingController();
  final _posStateController = TextEditingController(text: '27');
  final _intervalController = TextEditingController(text: '1');
  final _maxOccurrencesController = TextEditingController();
  String _selectedFrequency = 'MONTHLY';
  int _intervalCount = 1;
  String _endMode = 'NEVER';
  String? _selectedContactId;
  DateTime _nextDate = DateTime.now().add(const Duration(days: 7));
  DateTime? _endDate;
  final List<Map<String, dynamic>> _items = [];
  bool _isLoadingDetail = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().fetchContacts();
      context.read<ProductProvider>().fetchProducts();
      if (widget.isEdit) {
        _loadTemplate();
      }
    });
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    _posStateController.dispose();
    _intervalController.dispose();
    _maxOccurrencesController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    setState(() => _isLoadingDetail = true);
    final provider = context.read<RecurringInvoiceProvider>();
    final detail = await provider.fetchRecurringInvoiceDetail(widget.id!);
    if (!mounted) return;

    if (detail != null) {
      _templateNameController.text = detail.templateName;
      _posStateController.text = detail.posStateCode;
      _selectedFrequency = detail.frequency;
      _intervalCount = detail.intervalCount;
      _intervalController.text = detail.intervalCount.toString();
      _endMode = detail.endMode;
      _selectedContactId = detail.contactId;
      _nextDate = DateTime.tryParse(detail.nextDate) ?? _nextDate;
      _endDate = detail.endDate != null ? DateTime.tryParse(detail.endDate!) : null;
      _maxOccurrencesController.text = detail.maxOccurrences?.toString() ?? '';
      _items
        ..clear()
        ..addAll(detail.items.map((item) {
          return {
            'product_id': item.productId,
            'product_name': item.description ?? 'Product',
            'description': item.description,
            'quantity': item.quantity,
            'rate': item.rate,
            'discount': item.discount,
            'hsn_sac': item.hsnSac,
            'gst_rate': item.gstRate,
          };
        }));
    }

    setState(() => _isLoadingDetail = false);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactProvider>().contacts;
    final products = context.watch<ProductProvider>().products;

    if (_isLoadingDetail) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/recurring-invoices'),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                widget.isEdit ? 'Edit Recurring Invoice' : 'New Recurring Invoice',
                style: AppTypography.headlineLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            AppButton(
              label: _isSaving ? 'Saving...' : widget.isEdit ? 'Update Template' : 'Save Template',
              icon: Icons.save,
              onPressed: _isSaving ? null : _save,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionHeader(title: 'TEMPLATE DETAILS'),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _templateNameController,
                  decoration: const InputDecoration(labelText: 'Template Name *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _selectedContactId,
                  decoration: const InputDecoration(labelText: 'Customer *', border: OutlineInputBorder()),
                  items: contacts.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setState(() => _selectedContactId = v),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                AppSectionHeader(title: 'SCHEDULE'),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedFrequency,
                        decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
                          DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                          DropdownMenuItem(value: 'QUARTERLY', child: Text('Quarterly')),
                          DropdownMenuItem(value: 'YEARLY', child: Text('Yearly')),
                        ],
                        onChanged: (v) => setState(() => _selectedFrequency = v ?? 'MONTHLY'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(labelText: 'Interval', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        controller: _intervalController,
                        onChanged: (v) => _intervalCount = int.tryParse(v) ?? 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _endMode,
                  decoration: const InputDecoration(labelText: 'Ends', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'NEVER', child: Text('Never')),
                    DropdownMenuItem(value: 'ON_DATE', child: Text('On Date')),
                    DropdownMenuItem(value: 'AFTER_N', child: Text('After N Occurrences')),
                  ],
                  onChanged: (v) => setState(() {
                    _endMode = v ?? 'NEVER';
                    if (_endMode != 'ON_DATE') _endDate = null;
                    if (_endMode != 'AFTER_N') _maxOccurrencesController.clear();
                  }),
                ),
                if (_endMode != 'NEVER') ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildEndConditionField(),
                ],
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  onTap: _pickNextDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Next Invoice Date *',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(_formatDate(_nextDate.toIso8601String()))),
                        const Icon(Icons.calendar_today_outlined, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                AppSectionHeader(title: 'ITEMS'),
                const SizedBox(height: AppSpacing.md),
                ..._items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      title: Text(item['description'] ?? 'Item ${idx + 1}'),
                      subtitle: Text('${item['product_name'] ?? 'Product'} - ${item['quantity']} x ${_formatAmount(item['rate'])}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => setState(() => _items.removeAt(idx)),
                      ),
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: products.isEmpty ? null : _addItemDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _addItemDialog() {
    final products = context.read<ProductProvider>().products;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create at least one product before adding recurring invoice items')),
      );
      return;
    }

    var selectedProduct = products.first;
    final descCtrl = TextEditingController(text: selectedProduct.name);
    final qtyCtrl = TextEditingController(text: '1');
    final rateCtrl = TextEditingController(text: selectedProduct.salesPrice.toStringAsFixed(2));
    final hsnCtrl = TextEditingController(text: selectedProduct.hsnSac);
    final gstCtrl = TextEditingController(text: selectedProduct.gstRate.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedProduct.id,
                  decoration: const InputDecoration(labelText: 'Product *'),
                  items: products
                      .map((p) => DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (id) {
                    final product = products.firstWhere((p) => p.id == id, orElse: () => selectedProduct);
                    setDialogState(() {
                      selectedProduct = product;
                      descCtrl.text = product.name;
                      rateCtrl.text = product.salesPrice.toStringAsFixed(2);
                      hsnCtrl.text = product.hsnSac;
                      gstCtrl.text = product.gstRate.toStringAsFixed(2);
                    });
                  },
                ),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
                TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
                TextField(controller: rateCtrl, decoration: const InputDecoration(labelText: 'Rate'), keyboardType: TextInputType.number),
                TextField(controller: hsnCtrl, decoration: const InputDecoration(labelText: 'HSN/SAC'), keyboardType: TextInputType.number),
                TextField(controller: gstCtrl, decoration: const InputDecoration(labelText: 'GST Rate %'), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final quantity = double.tryParse(qtyCtrl.text) ?? 0;
                final rate = double.tryParse(rateCtrl.text) ?? -1;
                final gstRate = double.tryParse(gstCtrl.text) ?? -1;
                final hsnSac = hsnCtrl.text.trim();

                if (quantity <= 0 || rate < 0 || gstRate < 0 || hsnSac.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter valid product, quantity, rate, HSN/SAC, and GST rate')),
                  );
                  return;
                }

                setState(() {
                  _items.add({
                    'product_id': selectedProduct.id,
                    'product_name': selectedProduct.name,
                    'description': descCtrl.text.trim().isEmpty ? selectedProduct.name : descCtrl.text.trim(),
                    'quantity': quantity,
                    'rate': rate,
                    'discount': 0,
                    'hsn_sac': hsnSac,
                    'gst_rate': gstRate,
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndConditionField() {
    if (_endMode == 'ON_DATE') {
      return InkWell(
        onTap: _pickEndDate,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'End Date *',
            border: OutlineInputBorder(),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _endDate == null
                      ? 'Select end date'
                      : _formatDate(_endDate!.toIso8601String()),
                ),
              ),
              const Icon(Icons.calendar_today_outlined, size: 18),
            ],
          ),
        ),
      );
    }

    return TextField(
      controller: _maxOccurrencesController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Max Occurrences *',
        border: OutlineInputBorder(),
      ),
    );
  }

  Future<void> _pickNextDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _nextDate = picked);
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _nextDate,
      firstDate: _nextDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _save() async {
    if (_templateNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template name is required')));
      return;
    }
    if (_selectedContactId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a customer')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }
    if (_intervalCount < 1 || _intervalCount > 12) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Interval must be between 1 and 12')));
      return;
    }
    if (_endMode == 'ON_DATE' && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date is required')));
      return;
    }
    if (_endMode == 'ON_DATE' && _endDate!.isBefore(_nextDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date cannot be before next invoice date')));
      return;
    }
    final maxOccurrences = int.tryParse(_maxOccurrencesController.text.trim());
    if (_endMode == 'AFTER_N' && (maxOccurrences == null || maxOccurrences < 1)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max occurrences must be at least 1')));
      return;
    }

    setState(() => _isSaving = true);

    final payload = _buildPayload(maxOccurrences);

    final provider = context.read<RecurringInvoiceProvider>();
    final success = widget.isEdit
        ? await provider.updateRecurringInvoice(widget.id!, payload)
        : await provider.createRecurringInvoice(payload);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success && mounted) {
      context.go(widget.isEdit ? '/recurring-invoices/${widget.id}' : '/recurring-invoices');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Failed to save')),
      );
    }
  }

  Map<String, dynamic> _buildPayload(int? maxOccurrences) {
    return {
      'contact_id': _selectedContactId,
      'template_name': _templateNameController.text,
      'frequency': _selectedFrequency,
      'interval_count': _intervalCount,
      'next_date': _nextDate.toIso8601String().split('T')[0],
      'end_mode': _endMode,
      'end_date': _endMode == 'ON_DATE'
          ? _endDate!.toIso8601String().split('T')[0]
          : null,
      'max_occurrences': _endMode == 'AFTER_N' ? maxOccurrences : null,
      'pos_state_code': _posStateController.text,
      'items': _items.map((e) => {
        'product_id': e['product_id'],
        'description': e['description'],
        'quantity': e['quantity'],
        'rate': e['rate'],
        'discount': e['discount'] ?? 0,
        'hsn_sac': e['hsn_sac'],
        'gst_rate': e['gst_rate'],
      }).toList(),
    };
  }
}

class RecurringInvoiceDetailScreen extends StatefulWidget {
  final String id;
  const RecurringInvoiceDetailScreen({super.key, required this.id});
  @override
  State<RecurringInvoiceDetailScreen> createState() => _RecurringInvoiceDetailScreenState();
}

class _RecurringInvoiceDetailScreenState extends State<RecurringInvoiceDetailScreen> {
  RecurringInvoiceModel? _detail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<RecurringInvoiceProvider>();
    final detail = await provider.fetchRecurringInvoiceDetail(widget.id);
    if (mounted) setState(() { _detail = detail; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/recurring-invoices'),
            ),
            const SizedBox(width: AppSpacing.md),
            Text('Recurring Invoice', style: AppTypography.headlineLarge),
            const Spacer(),
            if (_detail != null) ...[
              AppButton(
                label: 'Edit',
                icon: Icons.edit_outlined,
                style: AppButtonStyle.secondary,
                onPressed: () => context.go('/recurring-invoices/${widget.id}/edit'),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Generate Now',
                icon: Icons.play_arrow,
                onPressed: () async {
                  final provider = context.read<RecurringInvoiceProvider>();
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await provider.generateInvoice(widget.id);
                  if (result != null && mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Invoice generated: ${result['invoice_number']}')),
                    );
                  }
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: _detail!.isActive ? 'Pause' : 'Resume',
                icon: _detail!.isActive ? Icons.pause : Icons.play_arrow,
                style: AppButtonStyle.secondary,
                onPressed: () async {
                  final provider = context.read<RecurringInvoiceProvider>();
                  await provider.updateRecurringInvoice(widget.id, {'is_active': !_detail!.isActive});
                  _load();
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_detail == null)
          const Center(child: Text('Not found'))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _infoCard('Template', _detail!.templateName)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _infoCard('Customer', _detail!.contact?.name ?? _detail!.contactName ?? '-')),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _infoCard('Status', _detail!.isActive ? 'Active' : 'Paused')),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: _infoCard('Frequency', _detail!.frequencyLabel)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _infoCard('Next Date', _formatDate(_detail!.nextDate))),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _infoCard('Generated', '${_detail!.occurrencesCreated} times')),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: _infoCard('End Condition', _detail!.endModeLabel)),
                      if (_detail!.endMode == 'ON_DATE') ...[
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: _infoCard('End Date', _formatDate(_detail!.endDate ?? ''))),
                      ],
                      if (_detail!.endMode == 'AFTER_N') ...[
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: _infoCard('Max Occurrences', '${_detail!.maxOccurrences ?? '-'}')),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  AppSectionHeader(title: 'ITEMS'),
                  const SizedBox(height: AppSpacing.md),
                  AppTable(
                    columns: const [
                      TableColumn(label: 'Description', width: 250),
                      TableColumn(label: 'Qty', width: 80),
                      TableColumn(label: 'Rate', width: 120),
                      TableColumn(label: 'GST %', width: 80),
                      TableColumn(label: 'Amount', width: 120),
                    ],
                    rows: _detail!.items.map((item) {
                      final amount = item.quantity * item.rate * (1 - item.discount / 100);
                      return AppTableRow(
                        cells: [
                          Text(item.description ?? '-', style: AppTypography.bodyMedium),
                          Text('${item.quantity}', style: AppTypography.bodySmall),
                          Text(_formatAmount(item.rate), style: AppTypography.bodySmall),
                          Text('${item.gstRate}%', style: AppTypography.bodySmall),
                          Text(_formatAmount(amount), style: AppTypography.amountTiny),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _infoCard(String label, String value) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelMedium.copyWith(color: AppColors.gray500)),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTypography.headlineSmall),
        ],
      ),
    );
  }
}
