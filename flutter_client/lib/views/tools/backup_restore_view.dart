import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/utils/download_stub.dart' if (dart.library.html) 'package:flutter_client/utils/download_web.dart';

class BackupRestoreView extends StatefulWidget {
  const BackupRestoreView({super.key});

  @override
  State<BackupRestoreView> createState() => _BackupRestoreViewState();
}

class _BackupRestoreViewState extends State<BackupRestoreView> {
  bool _isExporting = false;
  bool _isImporting = false;
  String? _error;
  String? _successMessage;

  Map<String, dynamic>? _pendingImportData;
  Map<String, int>? _pendingCounts;

  Future<void> _exportBackup() async {
    setState(() {
      _isExporting = true;
      _error = null;
      _successMessage = null;
      _pendingImportData = null;
      _pendingCounts = null;
    });

    try {
      final response = await ApiClient().get(
        Uri.parse('${ApiClient.baseUrl}/companies/${ApiClient.tenantId}/export'),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'apexbooks_backup_$timestamp.json';

        final json = const JsonEncoder.withIndent('  ').convert(data);
        final bytes = utf8.encode(json);

        if (kIsWeb) {
          triggerWebDownload(fileName, bytes);
          setState(() {
            _isExporting = false;
            _successMessage = 'Backup downloaded: $fileName';
          });
        } else {
          final savePath = await FilePicker.platform.saveFile(
            dialogTitle: 'Save ApexBooks Backup',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['json'],
            bytes: Uint8List.fromList(bytes),
          );

          setState(() {
            _isExporting = false;
            _successMessage = savePath == null ? 'Backup export cancelled' : 'Backup saved to $savePath';
          });
        }
      } else {
        setState(() {
          _isExporting = false;
          _error = 'Export failed (${response.statusCode})';
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

  Future<void> _pickAndRestore() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        dialogTitle: 'Select ApexBooks Backup (.json)',
        withData: true,
      );
    } catch (e) {
      setState(() => _error = 'Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;

    if (!picked.name.toLowerCase().endsWith('.json')) {
      setState(() => _error = 'Please select a valid .json backup file.');
      return;
    }

    setState(() {
      _isImporting = true;
      _error = null;
      _successMessage = null;
      _pendingImportData = null;
      _pendingCounts = null;
    });

    try {
      final bytes = picked.bytes;
      if (bytes == null) {
        throw Exception('Could not read file');
      }
      final content = utf8.decode(bytes);

      // Validate JSON structure
      final data = jsonDecode(content);
      if (data is! Map || !data.containsKey('tenant_id')) {
        throw Exception('Invalid backup file format');
      }

      final counts = <String, int>{};
      for (final key in ['contacts', 'products', 'invoices', 'bills', 'expenses', 'journal_entries', 'accounts']) {
        final list = data[key];
        if (list is List) counts[key] = list.length;
      }

      setState(() {
        _isImporting = false;
        _pendingImportData = data as Map<String, dynamic>;
        _pendingCounts = counts;
        _successMessage = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _error = 'Restore failed: $e';
        });
      }
    }
  }

  Future<void> _confirmImport() async {
    if (_pendingImportData == null) return;

    setState(() {
      _isImporting = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final response = await ApiClient().post(
        Uri.parse('${ApiClient.baseUrl}/companies/${ApiClient.tenantId}/import'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_pendingImportData),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final counts = result['counts'] as Map<String, dynamic>? ?? {};
        final totalInserted = counts.values.fold<int>(0, (sum, v) {
          if (v is Map) {
            return sum + ((v['inserted'] as int?) ?? 0);
          }
          return sum;
        });
        final totalSkipped = counts.values.fold<int>(0, (sum, v) {
          if (v is Map) {
            return sum + ((v['skipped'] as int?) ?? 0);
          }
          return sum;
        });

        setState(() {
          _isImporting = false;
          _pendingImportData = null;
          _pendingCounts = null;
          _successMessage = 'Import completed.\nInserted: $totalInserted  |  Skipped (already exist): $totalSkipped';
        });
      } else {
        final body = response.body.isNotEmpty ? response.body : 'Error ${response.statusCode}';
        setState(() {
          _isImporting = false;
          _error = 'Import failed: $body';
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

  void _cancelImport() {
    setState(() {
      _pendingImportData = null;
      _pendingCounts = null;
      _error = null;
      _successMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Export Data', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    const Text('Download a JSON backup of all your company data.'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isExporting ? null : _exportBackup,
                      icon: _isExporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download),
                      label: Text(_isExporting ? 'Exporting...' : 'Export Backup'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Restore Data', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    const Text('Select a previously exported .json backup file to restore.'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isImporting || _pendingImportData != null ? null : _pickAndRestore,
                      icon: _isImporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(_isImporting ? 'Reading...' : 'Select Backup File'),
                    ),
                  ],
                ),
              ),
            ),
            if (_pendingImportData != null && _pendingCounts != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                        const SizedBox(width: 8),
                        Text('Ready to Import', style: AppTextStyles.h3.copyWith(color: AppColors.warning)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('The following records were found in the backup:', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                    ..._pendingCounts!.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text('${e.key}', style: const TextStyle(fontSize: 13))),
                          Text('${e.value}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                    const SizedBox(height: 12),
                    const Text(
                      'Existing records with the same ID will be skipped. This action cannot be undone.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelImport,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isImporting ? null : _confirmImport,
                            icon: _isImporting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(_isImporting ? 'Importing...' : 'Confirm Import'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
              ),
            ],
            if (_successMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(8)),
                child: Text(_successMessage!, style: const TextStyle(color: AppColors.success)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
