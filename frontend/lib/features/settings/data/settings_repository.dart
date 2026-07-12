/// Repository for settings-related API calls: company profile, financial
/// years, and team management.
library;

import 'package:dio/dio.dart';

import '../../../core/network/dio_extensions.dart';
import '../../../core/result/result.dart';
import '../../auth/data/models/membership_models.dart';
import 'models/financial_year.dart';
import 'models/export_record.dart';
import 'models/gst_config.dart';
import 'models/preferences.dart';
import 'models/series.dart';
import 'models/team_member.dart';

class SettingsRepository {
  SettingsRepository(this._dio);
  final Dio _dio;

  // ---------------------------------------------------------------------------
  // Company Profile
  // ---------------------------------------------------------------------------

  /// `GET /companies/{id}` — full company profile.
  Future<Result<Company>> getCompany(String id) {
    return guardDio(() async {
      final res = await _dio.get('/companies/$id');
      return Company.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `PUT /companies/{id}` — update company profile.
  Future<Result<Company>> updateCompany(
    String id,
    Map<String, dynamic> data,
  ) {
    return guardDio(() async {
      final res = await _dio.put('/companies/$id', data: data);
      return Company.fromJson(res.data as Map<String, dynamic>);
    });
  }

  // ---------------------------------------------------------------------------
  // Financial Years
  // ---------------------------------------------------------------------------

  /// `GET /companies/{id}/financial-years` — list all financial years.
  Future<Result<List<FinancialYear>>> getFinancialYears(String companyId) {
    return guardDio(() async {
      final res = await _dio.get('/companies/$companyId/financial-years');
      return _parseList(res.data, FinancialYear.fromJson);
    });
  }

  /// `POST /companies/{id}/financial-years` — create a new financial year.
  Future<Result<FinancialYear>> createFinancialYear(
    String companyId, {
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return guardDio(() async {
      final res = await _dio.post(
        '/companies/$companyId/financial-years',
        data: {
          'name': name,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
        },
      );
      return FinancialYear.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `PUT /companies/{id}/financial-years/{fyId}` — set as current financial
  /// year. The backend is expected to toggle the flag server-side.
  Future<Result<void>> setCurrentFinancialYear(
    String companyId,
    String fyId,
  ) {
    return guardDio(() async {
      await _dio.put(
        '/companies/$companyId/financial-years/$fyId',
        data: {'is_current': true},
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Team Members
  // ---------------------------------------------------------------------------

  /// `GET /companies/{id}/members` — list all team members.
  Future<Result<List<TeamMember>>> getTeamMembers(String companyId) {
    return guardDio(() async {
      final res = await _dio.get('/companies/$companyId/members');
      return _parseList(res.data, TeamMember.fromJson);
    });
  }

  /// `POST /companies/{id}/members/invite` — send an invitation.
  Future<Result<void>> inviteMember(
    String companyId, {
    required String email,
    required String role,
  }) {
    return guardDio(() async {
      await _dio.post(
        '/companies/$companyId/members/invite',
        data: {'email': email, 'role': role},
      );
    });
  }

  /// `PUT /companies/{id}/members/{memberId}/role` — change a member's role.
  Future<Result<void>> updateMemberRole(
    String companyId,
    String memberId, {
    required String role,
  }) {
    return guardDio(() async {
      await _dio.put(
        '/companies/$companyId/members/$memberId/role',
        data: {'role': role},
      );
    });
  }

  /// `DELETE /companies/{id}/members/{memberId}` — remove a member.
  Future<Result<void>> removeMember(String companyId, String memberId) {
    return guardDio(() async {
      await _dio.delete('/companies/$companyId/members/$memberId');
    });
  }

  // ---------------------------------------------------------------------------
  // Invoice Series
  // ---------------------------------------------------------------------------

  /// `GET /settings/series` — list all numbering series.
  Future<Result<List<InvoiceSeries>>> getSeries() {
    return guardDio(() async {
      final res = await _dio.get('/settings/series');
      return _parseList(res.data, InvoiceSeries.fromJson);
    });
  }

  /// `POST /settings/series` — create a new numbering series.
  Future<Result<InvoiceSeries>> createSeries(Map<String, dynamic> data) {
    return guardDio(() async {
      final res = await _dio.post('/settings/series', data: data);
      return InvoiceSeries.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `PUT /settings/series/{id}` — update an existing series.
  Future<Result<InvoiceSeries>> updateSeries(
    String id,
    Map<String, dynamic> data,
  ) {
    return guardDio(() async {
      final res = await _dio.put('/settings/series/$id', data: data);
      return InvoiceSeries.fromJson(res.data as Map<String, dynamic>);
    });
  }

  // ---------------------------------------------------------------------------
  // Export / Import / Purge
  // ---------------------------------------------------------------------------

  /// `GET /companies/{id}/exports` — fetch export history.
  Future<Result<List<ExportRecord>>> getExportHistory(String companyId) {
    return guardDio(() async {
      final res = await _dio.get('/companies/$companyId/exports');
      return _parseList(res.data, ExportRecord.fromJson);
    });
  }

  /// `POST /companies/{id}/export` — trigger a new data export.
  Future<Result<ExportRecord>> triggerExport(String companyId) {
    return guardDio(() async {
      final res = await _dio.post('/companies/$companyId/export');
      return ExportRecord.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `POST /companies/{id}/import` — import company data.
  Future<Result<void>> importData(
    String companyId, {
    required List<int> fileBytes,
    required String fileName,
  }) {
    return guardDio(() async {
      await _dio.post(
        '/companies/$companyId/import',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
        }),
      );
    });
  }

  /// `POST /purge/request` — request a data purge (OTP sent).
  Future<Result<void>> requestPurge() {
    return guardDio(() async {
      await _dio.post('/purge/request');
    });
  }

  /// `POST /purge/verify` — verify purge with OTP.
  Future<Result<void>> verifyPurge(String otp) {
    return guardDio(() async {
      await _dio.post('/purge/verify', data: {'otp': otp});
    });
  }

  // ---------------------------------------------------------------------------
  // GST Configuration
  // ---------------------------------------------------------------------------

  /// `POST /companies/{id}/gst-toggle` — change GST tax mode.
  Future<Result<void>> toggleGstMode(String companyId, String taxMode) {
    return guardDio(() async {
      await _dio.post(
        '/companies/$companyId/gst-toggle',
        data: {'tax_mode': taxMode},
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Settings (preferences + GST config fields live under /settings)
  // ---------------------------------------------------------------------------

  /// `GET /settings` — fetch user preferences.
  Future<Result<UserPreferences>> getPreferences() {
    return guardDio(() async {
      final res = await _dio.get('/settings');
      return UserPreferences.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `PUT /settings` — update user preferences.
  Future<Result<UserPreferences>> updatePreferences(
    Map<String, dynamic> data,
  ) {
    return guardDio(() async {
      final res = await _dio.put('/settings', data: data);
      return UserPreferences.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `GET /settings` — fetch GST config (may share the same endpoint).
  Future<Result<GstConfig>> getGstConfig() {
    return guardDio(() async {
      final res = await _dio.get('/settings');
      return GstConfig.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `PUT /settings` — update GST-related settings fields.
  Future<Result<GstConfig>> updateGstConfig(Map<String, dynamic> data) {
    return guardDio(() async {
      final res = await _dio.put('/settings', data: data);
      return GstConfig.fromJson(res.data as Map<String, dynamic>);
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Parses a response body that may be a JSON array or an envelope with
  /// an `items` key.
  List<T> _parseList<T>(
    dynamic data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final list = <T>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) list.add(fromJson(item));
      }
    } else if (data is Map<String, dynamic> && data['items'] is List) {
      for (final item in data['items'] as List) {
        if (item is Map<String, dynamic>) list.add(fromJson(item));
      }
    }
    return list;
  }
}
