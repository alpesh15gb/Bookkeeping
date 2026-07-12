/// Repository for settings-related API calls: company profile, financial
/// years, and team management.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_extensions.dart';
import '../../../core/result/result.dart';
import '../../auth/data/models/membership_models.dart';
import 'models/financial_year.dart';
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
