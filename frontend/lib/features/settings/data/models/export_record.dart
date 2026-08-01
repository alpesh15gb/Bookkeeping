/// Export / import history model for backup and restore.
library;

import 'package:flutter/foundation.dart';

/// A single export record in the company's backup history.
@immutable
class ExportRecord {
  const ExportRecord({
    required this.id,
    required this.status,
    this.fileUrl,
    this.fileSize,
    required this.requestedAt,
    this.completedAt,
    this.errorMessage,
  });

  factory ExportRecord.fromJson(Map<String, dynamic> json) {
    return ExportRecord(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'pending',
      fileUrl: json['file_url'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
      requestedAt: DateTime.parse(json['requested_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      errorMessage: json['error_message'] as String?,
    );
  }

  final String id;
  final String status;
  final String? fileUrl;
  final int? fileSize;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final String? errorMessage;

  /// Human-readable file size.
  String get formattedSize {
    if (fileSize == null) return '—';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
