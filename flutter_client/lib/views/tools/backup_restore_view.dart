import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/views/shared/app_components.dart';

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

  Future<void> _exportBackup() async {
    setState(() {
      _isExporting = true;
      _error = null;
      _successMessage = null;
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
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ApexBooks Backup',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(json)),
        );

        setState(() {
          _isExporting = false;
          _successMessage = savePath == null ? 'Backup export cancelled' : 'Backup saved to $savePath';
        });
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

      // For now, just display summary — full restore would need backend endpoint
      final counts = <String, int>{};
      for (final key in ['contacts', 'products', 'invoices', 'bills', 'expenses', 'journal_entries']) {
        final list = data[key];
        if (list is List) counts[key] = list.length;
      }

      setState(() {
        _isImporting = false;
        _successMessage = 'Backup validated. Contains:\n${counts.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}';
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
                    const Text('Select a previously exported .json backup file to validate and inspect.'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isImporting ? null : _pickAndRestore,
                      icon: _isImporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(_isImporting ? 'Reading...' : 'Select Backup File'),
                    ),
                  ],
                ),
              ),
            ),
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
