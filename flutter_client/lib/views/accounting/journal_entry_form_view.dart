import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class JournalEntryFormView extends StatefulWidget {
  const JournalEntryFormView({super.key});

  @override
  State<JournalEntryFormView> createState() => _JournalEntryFormViewState();
}

class _JournalEntryFormViewState extends State<JournalEntryFormView> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _dateCtrl;
  final TextEditingController _refCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  bool _isSaving = false;

  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _fieldKeys = [];

  final List<_JournalFormLine> _lines = [];

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _dateCtrl = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );

    // Start with 2 empty lines (debit & credit)
    _lines.add(_JournalFormLine(direction: 'DEBIT'));
    _lines.add(_JournalFormLine(direction: 'CREDIT'));

    _fieldKeys.addAll([GlobalKey(), GlobalKey(), GlobalKey(), GlobalKey(), GlobalKey()]);

    Future.microtask(() {
      context.read<AccountingProvider>().fetchAccounts();
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _refCtrl.dispose();
    _descCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dateCtrl.text) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (date != null) {
      setState(() {
        _dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _addLine() {
    setState(() {
      _lines.add(_JournalFormLine());
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 2) {
      AppToast.error(context, 'A journal entry requires at least 2 lines');
      return;
    }
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
  }

  double get _totalDebits => _lines
      .where((l) => l.direction == 'DEBIT')
      .fold(0.0, (sum, l) => sum + (double.tryParse(l.amountCtrl.text) ?? 0.0));

  double get _totalCredits => _lines
      .where((l) => l.direction == 'CREDIT')
      .fold(0.0, (sum, l) => sum + (double.tryParse(l.amountCtrl.text) ?? 0.0));

  void _save() async {
    if (!_formKey.currentState!.validate()) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    // Validation: check if balanced
    final debits = double.parse(_totalDebits.toStringAsFixed(2));
    final credits = double.parse(_totalCredits.toStringAsFixed(2));

    if (debits != credits) {
      AppToast.error(context, 'Journal is out of balance by ₹${(debits - credits).abs().toStringAsFixed(2)}. Debits must equal Credits.');
      return;
    }

    if (debits <= 0) {
      AppToast.error(context, 'Journal total amount must be greater than zero');
      return;
    }

    // Validation: make sure all lines have accounts selected
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].accountId == null) {
        AppToast.error(context, 'Please select an account for line ${i + 1}');
        return;
      }
    }

    setState(() => _isSaving = true);

    final payload = {
      'entry_date': _dateCtrl.text,
      'reference_number': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      'description': _descCtrl.text.trim().isEmpty ? 'Manual Journal Entry' : _descCtrl.text.trim(),
      'lines': _lines.map((l) => {
        'account_id': l.accountId,
        'amount': (double.tryParse(l.amountCtrl.text) ?? 0),
        'direction': l.direction,
        'narration': l.narrationCtrl.text.trim().isEmpty ? null : l.narrationCtrl.text.trim(),
      }).toList(),
    };

    final provider = context.read<AccountingProvider>();
    final success = await provider.createJournal(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        AppToast.success(context, 'Journal entry posted successfully');
        Navigator.pop(context, true);
      } else {
        AppToast.error(context, provider.errorMessage ?? 'Failed to post journal entry');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final accounts = context.watch<AccountingProvider>().accountsList ?? [];

    final debits = _totalDebits;
    final credits = _totalCredits;
    final isBalanced = (debits - credits).abs() < 0.001;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('New Journal Entry'),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Balance: ${isBalanced ? 'Balanced' : 'Out of Balance'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isBalanced ? AppColors.success : AppColors.error,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandNavy,
                  foregroundColor: AppColors.textWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Entry', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
          children: [
            // Details Card
            _FormCard(
              title: 'JOURNAL DETAILS',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppDateField(
                          controller: _dateCtrl,
                          label: 'Entry Date *',
                          onTap: _pickDate,
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          controller: _refCtrl,
                          label: 'Reference Number (optional)',
                          prefixIcon: Icons.tag,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _descCtrl,
                    label: 'Description / Narration *',
                    prefixIcon: Icons.description_outlined,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Lines Card
            _FormCard(
              title: 'DOUBLE ENTRY LINES',
              trailing: ActionButton(
                label: 'Add Line',
                icon: Icons.add,
                tier: ActionTier.safe,
                onPressed: _addLine,
              ),
              child: Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _lines.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Index indicator
                          Container(
                            margin: const EdgeInsets.only(top: 14, right: 8),
                            child: Text('${i + 1}', style: AppTextStyles.caption),
                          ),

                          // Account Select Dropdown
                          Expanded(
                            flex: 5,
                            child: AppDropdown<String>(
                              value: line.accountId,
                              label: 'Account',
                              compact: true,
                              items: accounts.map((a) => DropdownMenuItem<String>(
                                value: a['id']?.toString(),
                                child: Text('${a['code'] ?? ""} - ${a['name']}'),
                              )).toList(),
                              onChanged: (v) => setState(() => line.accountId = v),
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Direction
                          Expanded(
                            flex: 3,
                            child: AppDropdown<String>(
                              value: line.direction,
                              label: 'Dr/Cr',
                              compact: true,
                              items: const [
                                DropdownMenuItem(value: 'DEBIT', child: Text('Debit (Dr)')),
                                DropdownMenuItem(value: 'CREDIT', child: Text('Credit (Cr)')),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => line.direction = v);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Amount
                          Expanded(
                            flex: 3,
                            child: AppTextField(
                              controller: line.amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              label: 'Amount',
                              compact: true,
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Amount is required';
                                final amt = double.tryParse(v);
                                if (amt == null) return 'Enter a valid number';
                                if (amt <= 0) return 'Amount must be greater than zero';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Remove action
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                              onPressed: () => _removeLine(i),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Balanced Summary Card
            _FormCard(
              title: 'BALANCE VERIFICATION',
              child: Column(
                children: [
                  SummaryRow(
                    label: 'Total Debits (Dr)',
                    value: '₹${debits.toStringAsFixed(2)}',
                    valueColor: const Color(0xFF067647),
                  ),
                  SummaryRow(
                    label: 'Total Credits (Cr)',
                    value: '₹${credits.toStringAsFixed(2)}',
                    valueColor: const Color(0xFFD92D20),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status', style: AppTextStyles.h3),
                      isBalanced
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Balanced',
                                style: TextStyle(color: Color(0xFF067647), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3F2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Out of Balance (₹${(debits - credits).abs().toStringAsFixed(2)})',
                                style: const TextStyle(color: Color(0xFFD92D20), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _JournalFormLine {
  String? accountId;
  String direction;
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController narrationCtrl = TextEditingController();

  _JournalFormLine({this.accountId, this.direction = 'DEBIT'});

  void dispose() {
    amountCtrl.dispose();
    narrationCtrl.dispose();
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _FormCard({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: AppTextStyles.labelSmall),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
