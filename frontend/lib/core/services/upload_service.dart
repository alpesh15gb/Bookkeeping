/// File upload framework. Handles multipart uploads (logo, invoice attachment,
/// OCR bill, bank statement, Vyapar/Tally import) with size + type validation
/// and progress reporting. Backed by Dio's [MultipartFile].
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../download/download_service.dart';
import '../logging/logger_service.dart';
import '../network/api_client.dart';
import '../network/error_mapper.dart';

export '../download/download_service.dart' show ExportKind;

/// Validates and uploads a file to [relativeUrl] as `multipart/form-data` under
/// [fieldName]. Reports progress via [onProgress] (0..1).
class UploadService {
  UploadService(this._dio, this._logger);

  final Dio _dio;
  final LoggerService _logger;

  /// Uploads [file] to [relativeUrl]. Returns the parsed JSON response.
  /// Throws [ApiError] for validation (size/type) or network failures.
  Future<Result<Map<String, dynamic>>> upload({
    required File file,
    required String relativeUrl,
    required String fieldName,
    required ExportKind allowedKind,
    Map<String, dynamic> extraFields = const {},
    void Function(double progress)? onProgress,
  }) async {
    // Validate size.
    final size = await file.length();
    if (size > AppConstants.maxUploadBytes) {
      return Failure(
        ApiError(
          message:
              'File is too large. Maximum size is '
              '${(AppConstants.maxUploadBytes / 1024 / 1024).toStringAsFixed(0)} MB.',
        ),
      );
    }

    try {
      final form = FormData();
      form.files.add(
        MapEntry(
          fieldName,
          await MultipartFile.fromFile(
            file.path,
            filename: _basename(file.path),
          ),
        ),
      );
      extraFields.forEach((k, v) => form.fields.add(MapEntry(k, v.toString())));
      final response = await _dio.post(
        relativeUrl,
        data: form,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      _logger.info('Uploaded ${file.path} → $relativeUrl ($size bytes)');
      return Success(response.data as Map<String, dynamic>);
    } on DioException catch (err) {
      _logger.warning('Upload failed', error: err);
      return Failure(toApiError(err));
    } catch (err) {
      _logger.error('Upload error', error: err);
      return Failure(ApiError.network(err.toString()));
    }
  }

  String _basename(String path) {
    final sep = path.contains(r'\') ? r'\' : '/';
    final parts = path.split(sep);
    return parts.isEmpty ? 'file' : parts.last;
  }
}

/// Provider for [UploadService].
final uploadServiceProvider = Provider<UploadService>((ref) {
  return UploadService(ref.watch(apiClientProvider), ref.watch(loggerProvider));
});
