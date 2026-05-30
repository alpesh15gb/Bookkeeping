import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:http/http.dart' as http;

class VyaparImportView extends StatefulWidget {
  const VyaparImportView({super.key});

  @override
  State<VyaparImportView> createState() => _VyaparImportViewState();
}

class _VyaparImportViewState extends State<VyaparImportView> {
  bool _isImporting = false;
  Map<String, dynamic>? _result;
  String? _error;
  String? _selectedFileName;

  Future<void> _pickAndImport() async {
    // Step 1: Pick the .vyb file using the native file picker
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vyb'],
        allowMultiple: false,
        dialogTitle: 'Select Vyapar Backup File (.vyb)',
        withData: true, // load bytes directly (works on all platforms)
      );
    } catch (e) {
      setState(() => _error = 'Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;

    // Validate extension
    if (!(picked.name.toLowerCase().endsWith('.vyb'))) {
      setState(() => _error = 'Please select a valid .vyb file from Vyapar.');
      return;
    }

    final fileBytes = picked.bytes;
    final filePath = picked.path;

    if (fileBytes == null && filePath == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }

    setState(() {
      _isImporting = true;
      _error = null;
      _result = null;
      _selectedFileName = picked.name;
    });

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/import/vyapar');
      final request = http.MultipartRequest('POST', uri);

      if (ApiClient.accessToken != null) {
        request.headers['Authorization'] = 'Bearer ${ApiClient.accessToken}';
      }
      if (ApiClient.tenantId != null) {
        request.headers['X-Tenant-ID'] = ApiClient.tenantId!;
      }

      // Use bytes if available (mobile/web), otherwise use path (desktop)
      if (fileBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: picked.name,
        ));
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('file', filePath!,
              filename: picked.name),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _isImporting = false;
          _result = jsonDecode(response.body);
        });
      } else {
        String msg = 'Import failed (${response.statusCode})';
        try {
          final body = jsonDecode(response.body);
          if (body is Map) msg = body['detail']?.toString() ?? msg;
        } catch (_) {}
        setState(() {
          _isImporting = false;
          _error = msg;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _error = 'Upload failed: $e';
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _result = null;
      _error = null;
      _selectedFileName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: _isImporting
          ? _buildLoading()
          : _result != null
              ? _buildResult()
              : _buildPicker(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Importing from Vyapar…',
              style: AppTextStyles.h3,
            ),
            const SizedBox(height: 6),
            Text(
              'Reading contacts, products, invoices and bills.\nThis may take a moment for large backups.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (_selectedFileName != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_zip_outlined,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      _selectedFileName!,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final errors = (r['errors'] as List?)?.cast<String>() ?? [];
    final total = (r['contacts_imported'] ?? 0) +
        (r['products_imported'] ?? 0) +
        (r['invoices_imported'] ?? 0) +
        (r['bills_imported'] ?? 0) +
        (r['expenses_imported'] ?? 0);

    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        const SizedBox(height: 40),

        // Success banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: AppRadius.card,
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Import Successful',
                        style: AppTextStyles.h3),
                    Text(
                      '$total records imported from $_selectedFileName',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Breakdown card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'IMPORT SUMMARY'),
              const SizedBox(height: 4),
              _summaryRow(
                  Icons.people_outline, 'Contacts',
                  r['contacts_imported'] ?? 0),
              _summaryRow(
                  Icons.inventory_2_outlined, 'Products',
                  r['products_imported'] ?? 0),
              _summaryRow(
                  Icons.receipt_outlined, 'Sales Invoices',
                  r['invoices_imported'] ?? 0),
              _summaryRow(
                  Icons.shopping_bag_outlined, 'Purchase Bills',
                  r['bills_imported'] ?? 0),
              _summaryRow(
                  Icons.account_balance_wallet_outlined, 'Expenses',
                  r['expenses_imported'] ?? 0),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_outlined,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text('${errors.length} Warning(s)',
                        style: AppTextStyles.label.copyWith(
                            color: AppColors.warning)),
                  ],
                ),
                const SizedBox(height: 6),
                ...errors.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $e', style: AppTextStyles.caption),
                    )),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        ActionButton(
          label: 'Import Another File',
          tier: ActionTier.safe,
          icon: Icons.file_upload_outlined,
          onPressed: _reset,
        ),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label, style: AppTextStyles.body)),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: count > 0
                  ? AppColors.brandNavy.withValues(alpha: 0.07)
                  : AppColors.borderLight,
              borderRadius: AppRadius.badge,
            ),
            child: Text(
              '$count',
              style: AppTextStyles.numeric.copyWith(
                color: count > 0
                    ? AppColors.brandNavy
                    : AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker() {
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        const SizedBox(height: 60),
        if (_error != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.errorBg,
              borderRadius: AppRadius.card,
              border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(_error!, style: AppTextStyles.bodySmall)),
                TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Dismiss')),
              ],
            ),
          ),
        ],

        // Hero illustration
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.brandNavy.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.file_upload_outlined,
              size: 40,
              color: AppColors.brandNavy,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text('Import from Vyapar', style: AppTextStyles.h2),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Select a .vyb backup file exported from Vyapar to import\nyour contacts, products, sales invoices, purchase bills,\nand expenses into this app.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),

        // What gets imported info card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'WHAT WILL BE IMPORTED'),
              const SizedBox(height: 4),
              _infoRow(Icons.people_outline, 'Contacts',
                  'Customers and vendors with GSTIN, address and phone'),
              _infoRow(Icons.inventory_2_outlined, 'Products',
                  'Items with HSN code, sale price, stock quantity'),
              _infoRow(Icons.receipt_outlined, 'Sales Invoices',
                  'All sale transactions with line items and GST breakdown'),
              _infoRow(Icons.shopping_bag_outlined, 'Purchase Bills',
                  'All purchase transactions with line items and GST'),
              _infoRow(
                  Icons.account_balance_wallet_outlined,
                  'Expenses',
                  'Business expenses with category mapping'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // File picker button
        ActionButton(
          label: 'Browse & Select .vyb File',
          tier: ActionTier.safe,
          icon: Icons.folder_open,
          onPressed: _pickAndImport,
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Supported format: Vyapar backup (.vyb)\nDuplicate contacts and products will be skipped.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.brandNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.bodyMedium),
                Text(subtitle,
                    style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
