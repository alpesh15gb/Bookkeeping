import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
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
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dateCtrl.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A journal entry requires at least 2 lines'), backgroundColor: AppColors.error),
      );
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
    if (!_formKey.currentState!.validate()) return;

    // Validation: check if balanced
    final debits = double.parse(_totalDebits.toStringAsFixed(2));
    final credits = double.parse(_totalCredits.toStringAsFixed(2));

    if (debits != credits) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Journal is out of balance by ₹${(debits - credits).abs().toStringAsFixed(2)}. Debits must equal Credits.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (debits <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journal total amount must be greater than zero'), backgroundColor: AppColors.error),
      );
      return;
    }

    // Validation: make sure all lines have accounts selected
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].accountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select an account for line ${i + 1}'), backgroundColor: AppColors.error),
        );
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
        'amount': double.parse(double.parse(l.amountCtrl.text).toStringAsFixed(2)),
        'direction': l.direction,
        'narration': l.narrationCtrl.text.trim().isEmpty ? null : l.narrationCtrl.text.trim(),
      }).toList(),
    };

    final provider = context.read<AccountingProvider>();
    final success = await provider.createJournal(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Journal entry posted successfully'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Failed to post journal entry'), backgroundColor: AppColors.error),
        );
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
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('SAVE'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
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
                        child: TextFormField(
                          controller: _dateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Entry Date *',
                            prefixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                          ),
                          readOnly: true,
                          onTap: _pickDate,
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _refCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Reference Number (optional)',
                            prefixIcon: Icon(Icons.tag, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description / Narration *',
                      prefixIcon: Icon(Icons.description_outlined, size: 16),
                    ),
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
                            child: DropdownButtonFormField<String>(
                              value: line.accountId,
                              decoration: const InputDecoration(
                                labelText: 'Account',
                                isDense: true,
                              ),
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
                            child: DropdownButtonFormField<String>(
                              value: line.direction,
                              decoration: const InputDecoration(
                                labelText: 'Dr/Cr',
                                isDense: true,
                              ),
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
                            child: TextFormField(
                              controller: line.amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Amount',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Amt';
                                final amt = double.tryParse(v);
                                if (amt == null || amt <= 0) return 'Invalid';
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
