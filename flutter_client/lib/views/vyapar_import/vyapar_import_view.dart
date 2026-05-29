import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/misc_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
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

  Future<void> _pickAndImport() async {
    final pathCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Vyapar Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the full path to your .vyb backup file:', style: AppTextStyles.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: pathCtrl,
              decoration: const InputDecoration(
                labelText: 'File path (.vyb)',
                hintText: r'C:\backups\mybackup.vyb',
                prefixIcon: Icon(Icons.folder_open, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );

    if (ok != true || pathCtrl.text.isEmpty) return;
    final path = pathCtrl.text.trim();

    final file = File(path);
    if (!await file.exists()) {
      setState(() => _error = 'File not found: $path');
      return;
    }

    setState(() { _isImporting = true; _error = null; _result = null; });

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/import/vyapar');
      final request = http.MultipartRequest('POST', uri);
      if (ApiClient.accessToken != null) {
        request.headers['Authorization'] = 'Bearer ${ApiClient.accessToken}';
      }
      if (ApiClient.tenantId != null) {
        request.headers['X-Tenant-ID'] = ApiClient.tenantId!;
      }
      request.files.add(await http.MultipartFile.fromPath('file', path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (mounted) {
        if (response.statusCode == 200) {
          setState(() { _isImporting = false; _result = jsonDecode(response.body); });
        } else {
          String msg = 'Import failed (${response.statusCode})';
          try {
            final body = jsonDecode(response.body);
            if (body is Map) msg = body['detail'] ?? msg;
          } catch (_) {}
          setState(() { _isImporting = false; _error = msg; });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _isImporting = false; _error = 'Failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: _isImporting
          ? const LoadingState(message: 'Importing data from Vyapar...')
          : _result != null
              ? ListView(
                  padding: AppSpacing.pagePadding,
                  children: [
                    const SizedBox(height: 40),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader(title: 'IMPORT COMPLETE'),
                          SummaryRow(label: 'Contacts', value: '${_result!['contacts_imported'] ?? 0}'),
                          SummaryRow(label: 'Products', value: '${_result!['products_imported'] ?? 0}'),
                          SummaryRow(label: 'Invoices', value: '${_result!['invoices_imported'] ?? 0}'),
                          SummaryRow(label: 'Bills', value: '${_result!['bills_imported'] ?? 0}'),
                          SummaryRow(label: 'Expenses', value: '${_result!['expenses_imported'] ?? 0}'),
                          if ((_result!['errors'] as List?)?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text('Warnings', style: AppTextStyles.labelSmall),
                            const SizedBox(height: 4),
                            ...(_result!['errors'] as List).map((e) => Text('• $e', style: AppTextStyles.caption)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ActionButton(label: 'Import Another File', tier: ActionTier.safe, onPressed: _pickAndImport),
                  ],
                )
              : ListView(
                  padding: AppSpacing.pagePadding,
                  children: [
                    const SizedBox(height: 80),
                    if (_error != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: AppRadius.card, border: Border.all(color: AppColors.error.withValues(alpha: 0.3))),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_error!, style: AppTextStyles.bodySmall)),
                          TextButton(onPressed: _pickAndImport, child: const Text('Retry')),
                        ]),
                      ),
                    ],
                    const EmptyState(
                      icon: Icons.file_upload_outlined,
                      title: 'Import from Vyapar',
                      subtitle: 'Enter the path to a .vyb backup file to import contacts, products, invoices, bills, and expenses',
                    ),
                    const SizedBox(height: 24),
                    ActionButton(label: 'Select .vyb File', tier: ActionTier.safe, icon: Icons.folder_open, onPressed: _pickAndImport),
                  ],
                ),
    );
  }
}
