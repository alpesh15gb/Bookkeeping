/// Download manager. ApexBooks reports/exports are served as binary responses
/// (PDF/Excel/CSV). This service fetches them via Dio with `responseType:
/// bytes`, saves to the platform's downloads/documents directory, and (on
/// desktop) opens a save dialog. Mobile uses the app documents dir + a share
/// sheet. Never blocks the UI — callers show a progress dialog via
/// [DialogService].
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../logging/logger_service.dart';
import '../network/api_client.dart';
import '../result/result.dart';

export '../errors/api_error.dart' show ApiError;
export '../result/result.dart' show Result, Success, Failure;

/// The kind of export, used to pick a sensible filename + extension.
enum ExportKind { pdf, excel, csv, json }

extension ExportKindX on ExportKind {
  String get extension => switch (this) {
    ExportKind.pdf => 'pdf',
    ExportKind.excel => 'xlsx',
    ExportKind.csv => 'csv',
    ExportKind.json => 'json',
  };
  String get mimeType => switch (this) {
    ExportKind.pdf => 'application/pdf',
    ExportKind.excel =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ExportKind.csv => 'text/csv',
    ExportKind.json => 'application/json',
  };
}

/// Result of a successful download.
class DownloadResult {
  const DownloadResult({required this.path, required this.bytes});
  final String path;
  final int bytes;
}

/// Central download service.
class DownloadService {
  DownloadService(this._dio, this._logger);

  final Dio _dio;
  final LoggerService _logger;

  /// Fetches [relativeUrl] (e.g. `/reports/balance-sheet/pdf`) as bytes and
  /// saves it under [filename] (without extension) in the platform documents
  /// directory. Returns the absolute path of the saved file.
  Future<Result<DownloadResult>> download({
    required String relativeUrl,
    required String filename,
    required ExportKind kind,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        relativeUrl,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data ?? const <int>[];
      final dir = await _saveDir();
      final file = File('${dir.path}/$filename.${kind.extension}');
      await file.writeAsBytes(bytes);
      _logger.info('Downloaded ${bytes.length} bytes → ${file.path}');
      return Success(DownloadResult(path: file.path, bytes: bytes.length));
    } on DioException catch (err) {
      _logger.warning('Download failed', error: err);
      return Failure(_mapError(err));
    } catch (err) {
      _logger.error('Download error', error: err);
      return Failure(_mapError(err));
    }
  }

  Future<Directory> _saveDir() {
    // Desktop → Downloads; mobile → app documents.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return getDownloadsDirectory().then(
        (d) => d ?? getApplicationDocumentsDirectory(),
      );
    }
    return getApplicationDocumentsDirectory();
  }

  // Reuse the app error mapping for the network case.
  ApiError _mapError(Object err) {
    if (err is DioException) {
      final status = err.response?.statusCode;
      final data = err.response?.data;
      String message = 'Download failed.';
      if (data is Map && data['detail'] is String) {
        message = data['detail'] as String;
      } else if (status != null) {
        message = 'Download failed (HTTP $status).';
      }
      return ApiError(message: message, statusCode: status);
    }
    return ApiError.network(err.toString());
  }
}

/// Provider for [DownloadService].
final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService(
    ref.watch(apiClientProvider),
    ref.watch(loggerProvider),
  );
});
