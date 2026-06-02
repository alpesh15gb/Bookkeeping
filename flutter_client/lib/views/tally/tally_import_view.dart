import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/utils/download_stub.dart' if (dart.library.html) 'package:flutter_client/utils/download_web.dart';

class TallyImportView extends StatefulWidget {
  const TallyImportView({super.key});

  @override
  State<TallyImportView> createState() => _TallyImportViewState();
}

class _TallyImportViewState extends State<TallyImportView> {
  bool _isImporting = false;
  bool _isExporting = false;
  Map<String, dynamic>? _result;
  String? _error;
  String? _successMessage;
  String? _selectedFileName;

  Future<void> _pickAndImport() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        allowMultiple: false,
        dialogTitle: 'Select Tally XML File',
        withData: true,
      );
    } catch (e) {
      setState(() => _error = 'Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    if (!picked.name.toLowerCase().endsWith('.xml')) {
      setState(() => _error = 'Please select a valid .xml file from Tally.');
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
      _successMessage = null;
      _selectedFileName = picked.name;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/tally/import'),
      );
      request.headers['Authorization'] = 'Bearer ${ApiClient.accessToken}';
      request.headers['X-Tenant-ID'] = ApiClient.tenantId ?? '';

      if (fileBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: picked.name,
        ));
      } else if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: picked.name,
        ));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isImporting = false;
          _result = data is Map<String, dynamic> ? data : {};
        });
      } else {
        String errMsg = 'Import failed';
        try {
          final data = jsonDecode(response.body);
          errMsg = data['detail'] ?? errMsg;
        } catch (_) {}
        setState(() {
          _isImporting = false;
          _error = '$errMsg (${response.statusCode})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _error = 'Import error: $e';
        });
      }
    }
  }

  Future<void> _exportTallyXml() async {
    setState(() {
      _isExporting = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final response = await ApiClient().get(
        Uri.parse('${ApiClient.baseUrl}/tally/export'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'tally_export_$timestamp.xml';

        if (kIsWeb) {
          triggerWebDownload(fileName, response.bodyBytes);
          setState(() {
            _isExporting = false;
            _successMessage = 'Tally export downloaded: $fileName';
          });
        } else {
          final savePath = await FilePicker.platform.saveFile(
            dialogTitle: 'Save Tally Export',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['xml'],
            bytes: response.bodyBytes,
          );

          setState(() {
            _isExporting = false;
            _successMessage = savePath == null
                ? 'Export cancelled'
                : 'Export saved to $savePath';
          });
        }
      } else {
        String errMsg = 'Export failed';
        try {
          final data = jsonDecode(response.body);
          errMsg = data['detail'] ?? errMsg;
        } catch (_) {}
        setState(() {
          _isExporting = false;
          _error = '$errMsg (${response.statusCode})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _error = 'Export error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final padding = isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: ListView(
        padding: padding,
        children: [
          Text('Tally Import / Export', style: AppTextStyles.h2),
          const SizedBox(height: 8),
          Text(
            'Import data from Tally XML or export your ApexBooks data as Tally-compatible XML.',
            style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),

          // Import Section
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.upload_file_rounded, color: Color(0xFF2E7D32), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Import from Tally', style: AppTextStyles.h3),
                          const SizedBox(height: 2),
                          Text(
                            'Import contacts, products, invoices, bills and payments from Tally XML export.',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_selectedFileName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Text(_selectedFileName!, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isImporting ? null : _pickAndImport,
                    icon: _isImporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(_isImporting ? 'Importing...' : 'Select Tally XML File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Export Section
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brandNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.download_rounded, color: AppColors.brandNavy, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Export to Tally', style: AppTextStyles.h3),
                          const SizedBox(height: 2),
                          Text(
                            'Download all your data as Tally-compatible XML file.',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportTallyXml,
                    icon: _isExporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_isExporting ? 'Exporting...' : 'Export as Tally XML'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Status Messages
          if (_error != null)
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: TextStyle(color: AppColors.error))),
                ],
              ),
            ),
          if (_successMessage != null)
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_successMessage!, style: TextStyle(color: AppColors.success))),
                ],
              ),
            ),

          // Import Results
          if (_result != null) ...[
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Import Summary', style: AppTextStyles.h3),
                  const SizedBox(height: 12),
                  _summaryRow('Contacts', _result!['contacts_imported'] ?? 0),
                  _summaryRow('Products', _result!['products_imported'] ?? 0),
                  _summaryRow('Invoices', _result!['invoices_imported'] ?? 0),
                  _summaryRow('Bills', _result!['bills_imported'] ?? 0),
                  _summaryRow('Payments', _result!['payments_imported'] ?? 0),
                  if ((_result!['errors'] as List?)?.isNotEmpty == true) ...[
                    const Divider(),
                    Text('Errors:', style: AppTextStyles.labelSmall.copyWith(color: AppColors.error)),
                    const SizedBox(height: 4),
                    ...((_result!['errors'] as List).map((e) => Text(
                      '• $e',
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                    ))),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supported Formats', style: AppTextStyles.h3),
                const SizedBox(height: 8),
                _infoRow(Icons.description_outlined, 'Tally XML', 'Export from Tally Prime / Tally.ERP 9 → Gateway of Tally → Display → List of Accounts → Export.'),
                const SizedBox(height: 8),
                _infoRow(Icons.info_outline, 'Note', 'Import maps Tally Ledgers → Contacts, Stock Items → Products, Sales/Purchase Vouchers → Invoices/Bills.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.body),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: count > 0 ? AppColors.success.withValues(alpha: 0.1) : AppColors.border,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: AppTextStyles.labelSmall.copyWith(
                color: count > 0 ? AppColors.success : AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.caption,
              children: [
                TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
