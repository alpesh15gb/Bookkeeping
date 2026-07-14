/// Repository for settings-related API calls: company profile, financial
/// years, and team management.
library;

import 'package:dio/dio.dart';

import '../../../core/network/dio_extensions.dart';
import '../../../core/result/result.dart';
import '../../auth/data/models/membership_models.dart';
import 'models/financial_year.dart';
import 'models/gst_config.dart';
import 'models/preferences.dart';
import 'models/series.dart';
import 'models/team_member.dart';
import 'models/tenant_settings.dart';

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
  Future<Result<Company>> updateCompany(String id, Map<String, dynamic> data) {
    return guardDio(() async {
      final res = await _dio.put('/companies/$id', data: data);
      return Company.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<TenantSettings>> getTenantSettings() {
    return guardDio(() async {
      final res = await _dio.get('/settings');
      return TenantSettings.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<TenantSettings>> updateTenantSettings(
    Map<String, dynamic> data,
  ) {
    return guardDio(() async {
      final res = await _dio.put('/settings', data: data);
      return TenantSettings.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<String>> uploadLogo({
    required List<int> bytes,
    required String filename,
  }) {
    return guardDio(() async {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _dio.post('/settings/logo', data: form);
      final data = Map<String, dynamic>.from(res.data as Map);
      return data['logo_url'] as String;
    });
  }

  // ---------------------------------------------------------------------------
  // Financial Years
  // ---------------------------------------------------------------------------

  /// `GET /financial-years` — list all financial years.
  Future<Result<List<FinancialYear>>> getFinancialYears(String companyId) {
    return guardDio(() async {
      final res = await _dio.get('/financial-years');
      return _parseList(res.data, FinancialYear.fromJson);
    });
  }

  /// `POST /financial-years` — create a new financial year.
  Future<Result<FinancialYear>> createFinancialYear(
    String companyId, {
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return guardDio(() async {
      final res = await _dio.post(
        '/financial-years',
        data: {
          'name': name,
          'start_date': startDate.toIso8601String().split('T')[0],
          'end_date': endDate.toIso8601String().split('T')[0],
        },
      );
      return FinancialYear.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `POST /financial-years/switch` — set as current financial year.
  Future<Result<void>> setCurrentFinancialYear(String companyId, String fyId) {
    return guardDio(() async {
      await _dio.post(
        '/financial-years/switch',
        data: {'financial_year_id': fyId},
      );
    });
  }

  Future<Result<void>> closeFinancialYear(String fyId) {
    return guardDio(() async {
      await _dio.post('/financial-years/$fyId/close');
    });
  }

  Future<Result<void>> reopenFinancialYear(String fyId, String reason) {
    return guardDio(() async {
      await _dio.post(
        '/financial-years/$fyId/reopen',
        queryParameters: {'reason': reason},
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

  /// `POST /companies/{id}/invite` — send an invitation.
  Future<Result<void>> inviteMember(
    String companyId, {
    required String email,
    required String role,
  }) {
    return guardDio(() async {
      await _dio.post(
        '/companies/$companyId/invite',
        data: {'email': email, 'role': role},
      );
    });
  }

  /// `PUT /companies/{id}/members/{userId}` — change a member's role.
  Future<Result<void>> updateMemberRole(
    String companyId,
    String memberId, {
    required String role,
  }) {
    return guardDio(() async {
      await _dio.put(
        '/companies/$companyId/members/$memberId',
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

  /// `GET /companies/{id}/export` — trigger and fetch data export.
  Future<Result<Map<String, dynamic>>> triggerExport(String companyId) {
    return guardDio(() async {
      final res = await _dio.get('/companies/$companyId/export');
      return Map<String, dynamic>.from(res.data as Map);
    });
  }

  /// `POST /companies/{id}/import` — import company data.
  Future<Result<void>> importData(
    String companyId, {
    required Map<String, dynamic> backup,
  }) {
    return guardDio(() async {
      await _dio.post('/companies/$companyId/import', data: backup);
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
  Future<Result<UserPreferences>> updatePreferences(Map<String, dynamic> data) {
    return guardDio(() async {
      final current = await _dio.get('/settings');
      final currentJson = Map<String, dynamic>.from(current.data as Map);
      final display = currentJson['display_settings'] is Map
          ? Map<String, dynamic>.from(currentJson['display_settings'] as Map)
          : <String, dynamic>{};
      display.addAll({
        if (data['date_format'] != null) 'date_format': data['date_format'],
        if (data['number_format'] != null)
          'number_format': data['number_format'],
        if (data['theme_mode'] != null) 'theme_mode': data['theme_mode'],
        if (data['timezone'] != null) 'timezone': data['timezone'],
      });
      final res = await _dio.put(
        '/settings',
        data: {
          if (data['currency'] != null) 'currency': data['currency'],
          'display_settings': display,
        },
      );
      return UserPreferences.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `GET /settings` — fetch GST config (may share the same endpoint).
  Future<Result<GstConfig>> getGstConfig(String companyId) {
    return guardDio(() async {
      final company = await _dio.get('/companies/$companyId');
      final settings = await _dio.get('/settings');
      final merged = Map<String, dynamic>.from(settings.data as Map)
        ..addAll(Map<String, dynamic>.from(company.data as Map));
      return GstConfig.fromJson(merged);
    });
  }

  /// `PUT /settings` — update GST-related settings fields.
  Future<Result<GstConfig>> updateGstConfig(
    String companyId,
    GstConfig config,
  ) {
    return guardDio(() async {
      await _dio.post(
        '/companies/$companyId/gst-toggle',
        data: {'tax_mode': config.taxMode},
      );
      final current = await _dio.get('/settings');
      final currentJson = Map<String, dynamic>.from(current.data as Map);
      final extra = currentJson['extra_settings'] is Map
          ? Map<String, dynamic>.from(currentJson['extra_settings'] as Map)
          : <String, dynamic>{};
      if (config.registrationType != null) {
        extra['gst_registration_type'] = config.registrationType;
      }
      if (config.filingFrequency != null) {
        extra['gst_filing_frequency'] = config.filingFrequency;
      }
      final settingsResponse = await _dio.put(
        '/settings',
        data: {
          'gst_enabled': config.taxMode != TaxMode.nonGst,
          if (config.stateCode != null) 'origin_state_code': config.stateCode,
          'extra_settings': extra,
        },
      );
      final companyResponse = await _dio.get('/companies/$companyId');
      final merged = Map<String, dynamic>.from(settingsResponse.data as Map)
        ..addAll(Map<String, dynamic>.from(companyResponse.data as Map));
      return GstConfig.fromJson(merged);
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
