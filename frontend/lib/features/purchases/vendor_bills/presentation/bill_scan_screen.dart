/// Purchase bill OCR upload, review, correction, and save workflow.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/states.dart';

class BillScanScreen extends ConsumerStatefulWidget {
  const BillScanScreen({super.key});

  @override
  ConsumerState<BillScanScreen> createState() => _BillScanScreenState();
}

class _BillScanScreenState extends ConsumerState<BillScanScreen> {
  Map<String, dynamic>? _preview;
  bool _scanning = false;
  bool _saving = false;
  String _progress = '';
  String? _error;
  Uint8List? _sourceBytes;
  String? _sourceName;

  Future<void> _chooseAndScan() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'tif',
        'tiff',
        'bmp',
        'pdf',
      ],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    if (file.bytes == null) {
      setState(
        () => _error =
            'The selected file could not be read. Please select it again.',
      );
      return;
    }
    setState(() {
      _scanning = true;
      _preview = null;
      _error = null;
      _sourceBytes = file.bytes;
      _sourceName = file.name;
      _progress = 'Uploading ${file.name}…';
    });
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.post<Map<String, dynamic>>(
        '/bills/scan-preview',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
          'confidence': .3,
        }),
      );
      var body = Map<String, dynamic>.from(response.data ?? const {});
      final jobId = body['job_id']?.toString();
      if (jobId != null) {
        for (var attempt = 0; attempt < 80 && mounted; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          final poll = await dio.get<Map<String, dynamic>>(
            '/bills/scan-status/$jobId',
          );
          body = Map<String, dynamic>.from(poll.data ?? const {});
          if (poll.statusCode == 200 && body['vendor'] is Map) break;
          if (mounted)
            setState(
              () => _progress = body['progress']?.toString() ?? 'Reading bill…',
            );
        }
      }
      if (!mounted) return;
      if (body['vendor'] is! Map) {
        throw StateError(
          'OCR did not finish in time. Please retry with a clearer scan.',
        );
      }
      _normalizePreview(body);
      setState(() {
        _preview = body;
        _progress = '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _normalizePreview(Map<String, dynamic> body) {
    body['vendor'] = Map<String, dynamic>.from(body['vendor'] as Map);
    final vendor = body['vendor'] as Map<String, dynamic>;
    final gstin = vendor['gstin']?.toString() ?? '';
    vendor['state_code'] ??= gstin.length == 15 ? gstin.substring(0, 2) : '';
    body['line_items'] = ((body['line_items'] as List?) ?? const [])
        .map((line) => Map<String, dynamic>.from(line as Map))
        .toList();
  }

  Future<void> _save() async {
    if (_preview == null || _saving) return;
    final vendor = Map<String, dynamic>.from(_preview!['vendor'] as Map);
    final lines = (_preview!['line_items'] as List)
        .cast<Map<String, dynamic>>();
    if ((vendor['name']?.toString().trim() ?? '').isEmpty || lines.isEmpty) {
      setState(
        () => _error = 'Vendor name and at least one bill line are required.',
      );
      return;
    }
    final stateCode = vendor['state_code']?.toString() ?? '';
    if (!RegExp(r'^\d{2}$').hasMatch(stateCode)) {
      setState(
        () => _error =
            'Enter the vendor’s two-digit GST state code before saving.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(
            '/bills/scan-save',
            data: {
              'vendor': vendor,
              'bill': {
                'bill_number': _preview!['bill_number'],
                'issue_date': _preview!['bill_date'],
                'due_date': _preview!['due_date'],
                'pos_state_code': stateCode,
                'reference_number': _preview!['po_number'],
                'notes':
                    'Created from OCR scan; source values reviewed by user.',
              },
              'line_items': lines,
            },
          );
      if (!mounted) return;
      ref
          .read(notificationServiceProvider)
          .success(
            context,
            'Bill ${response.data?['bill_number'] ?? ''} created as draft. Review and post it when ready.',
            title: 'Purchase bill created',
          );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null)
        return data['detail'].toString();
      if (error.response?.statusCode == 503)
        return 'OCR is temporarily unavailable. Please enter the bill manually or try again.';
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Scan Purchase Bill'),
        actions: [
          if (_preview != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving…' : 'Create Draft Bill'),
              ),
            ),
        ],
      ),
      body: _scanning
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LoadingSpinner(size: 38),
                  const SizedBox(height: 16),
                  Text(_progress.isEmpty ? 'Reading bill…' : _progress),
                  const SizedBox(height: 6),
                  Text(
                    'OCR can take up to two minutes.',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ],
              ),
            )
          : _preview == null
          ? _uploadPrompt(colors)
          : _review(colors),
    );
  }

  Widget _uploadPrompt(ApexColors colors) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ApexCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 54,
                color: colors.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Turn a vendor invoice into a draft bill',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload a clear image or PDF. ApexBooks extracts the vendor, invoice number, dates, GST and line items. Nothing is posted until you review and post the resulting draft.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _chooseAndScan,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose Image or PDF'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _review(ApexColors colors) {
    final vendor = _preview!['vendor'] as Map<String, dynamic>;
    final lines = (_preview!['line_items'] as List)
        .cast<Map<String, dynamic>>();
    final form = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: colors.danger)),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Review extracted details',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: _chooseAndScan,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Scan another'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ApexCard(
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _field(
                'Vendor name *',
                vendor['name'],
                (v) => vendor['name'] = v,
                300,
              ),
              _field(
                'GSTIN',
                vendor['gstin'],
                (v) => vendor['gstin'] = v.toUpperCase(),
                230,
              ),
              _field(
                'State code *',
                vendor['state_code'],
                (v) => vendor['state_code'] = v,
                130,
              ),
              _field(
                'Bill number',
                _preview!['bill_number'],
                (v) => _preview!['bill_number'] = v,
                190,
              ),
              _field(
                'Bill date',
                _preview!['bill_date'],
                (v) => _preview!['bill_date'] = v,
                160,
              ),
              _field(
                'Due date',
                _preview!['due_date'],
                (v) => _preview!['due_date'] = v,
                160,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(lines.length, (index) {
          final line = lines[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ApexCard(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _field(
                    'Item description',
                    line['product_name'],
                    (v) => line['product_name'] = v,
                    300,
                  ),
                  SizedBox(
                    width: 125,
                    child: DropdownButtonFormField<String>(
                      initialValue: (line['product_type'] ?? 'GOODS')
                          .toString(),
                      decoration: const InputDecoration(labelText: 'Item type'),
                      items: const [
                        DropdownMenuItem(value: 'GOODS', child: Text('Goods')),
                        DropdownMenuItem(
                          value: 'SERVICE',
                          child: Text('Service'),
                        ),
                      ],
                      onChanged: (value) => line['product_type'] = value,
                    ),
                  ),
                  _field(
                    'HSN/SAC',
                    line['hsn_sac'],
                    (v) => line['hsn_sac'] = v,
                    120,
                  ),
                  _numberField(
                    'Qty',
                    line['quantity'],
                    (v) => line['quantity'] = v,
                    90,
                  ),
                  _numberField(
                    'Rate',
                    line['rate'],
                    (v) => line['rate'] = v,
                    120,
                  ),
                  _numberField(
                    'GST %',
                    line['gst_rate'],
                    (v) => line['gst_rate'] = v,
                    90,
                  ),
                  IconButton(
                    tooltip: 'Remove line',
                    onPressed: lines.length == 1
                        ? null
                        : () => setState(() => lines.removeAt(index)),
                    icon: Icon(Icons.delete_outline, color: colors.danger),
                  ),
                ],
              ),
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(
              () => lines.add({
                'product_id': null,
                'product_name': '',
                'product_type': 'GOODS',
                'hsn_sac': '000000',
                'quantity': 1.0,
                'rate': 0.0,
                'gst_rate': 0.0,
              }),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add missing line'),
          ),
        ),
      ],
    );
    final sourceName = _sourceName?.toLowerCase() ?? '';
    final isImage = const [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'bmp',
    ].any((extension) => sourceName.endsWith('.$extension'));
    if (!isImage ||
        _sourceBytes == null ||
        MediaQuery.sizeOf(context).width < 1100) {
      return form;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 390,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 0, 20),
            child: ApexCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sourceName ?? 'Source document',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: InteractiveViewer(
                      minScale: .5,
                      maxScale: 5,
                      child: Center(
                        child: Image.memory(
                          _sourceBytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Text(
                            'Preview unavailable. The extracted fields remain editable.',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: form),
      ],
    );
  }

  Widget _field(
    String label,
    Object? value,
    ValueChanged<String> changed,
    double width,
  ) => SizedBox(
    width: width,
    child: TextFormField(
      initialValue: value?.toString() ?? '',
      decoration: InputDecoration(labelText: label),
      onChanged: changed,
    ),
  );

  Widget _numberField(
    String label,
    Object? value,
    ValueChanged<double> changed,
    double width,
  ) => SizedBox(
    width: width,
    child: TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => changed(double.tryParse(value) ?? 0),
    ),
  );
}
