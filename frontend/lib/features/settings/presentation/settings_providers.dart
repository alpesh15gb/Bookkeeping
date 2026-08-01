/// Shared providers for Settings screens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/models/membership_models.dart';
import '../data/models/financial_year.dart';
import '../data/models/gst_config.dart';
import '../data/models/preferences.dart';
import '../data/models/series.dart';
import '../data/models/export_record.dart';
import '../data/models/team_member.dart';
import '../data/models/tenant_settings.dart';
import '../data/settings_repository.dart';
import '../../auth/presentation/auth_controller.dart';

/// Provider for [SettingsRepository].
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(apiClientProvider));
});

/// Fetches the full Company profile by ID.
final companyProfileProvider = FutureProvider.family<Company, String>((
  ref,
  id,
) async {
  final repo = ref.watch(settingsRepositoryProvider);
  final result = await repo.getCompany(id);
  return switch (result) {
    Success<Company>(:final value) => value,
    Failure<Company>(:final error) => throw error,
    _ => throw const ApiError(message: 'Unexpected response.'),
  };
});

/// Operational settings for the active tenant (`GET /settings`).
final tenantSettingsProvider = FutureProvider<TenantSettings>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return _unwrapResult(repo.getTenantSettings());
});

/// Fetches the list of FinancialYears for a company.
final financialYearListProvider =
    FutureProvider.family<List<FinancialYear>, String>((ref, companyId) async {
      final repo = ref.watch(settingsRepositoryProvider);
      final result = await repo.getFinancialYears(companyId);
      return switch (result) {
        Success<List<FinancialYear>>(:final value) => value,
        Failure<List<FinancialYear>>(:final error) => throw error,
        _ => throw const ApiError(message: 'Unexpected response.'),
      };
    });

/// Fetches the list of TeamMembers for a company.
final teamMemberListProvider = FutureProvider.family<List<TeamMember>, String>((
  ref,
  companyId,
) async {
  final repo = ref.watch(settingsRepositoryProvider);
  final result = await repo.getTeamMembers(companyId);
  return switch (result) {
    Success<List<TeamMember>>(:final value) => value,
    Failure<List<TeamMember>>(:final error) => throw error,
    _ => throw const ApiError(message: 'Unexpected response.'),
  };
});

// ---------------------------------------------------------------------------
// Invoice Series
// ---------------------------------------------------------------------------

/// Fetches all numbering series from `/settings/series`.
final invoiceSeriesListProvider = FutureProvider<List<InvoiceSeries>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return _unwrapResult(repo.getSeries());
});

// ---------------------------------------------------------------------------
// GST Configuration
// ---------------------------------------------------------------------------

/// Combines company tax mode/GSTIN with operational GST settings.
final gstConfigProvider = FutureProvider<GstConfig>((ref) {
  final companyId = ref
      .watch(authControllerProvider)
      .activeMembership
      ?.tenantId;
  if (companyId == null) {
    throw const ApiError(message: 'No company selected.');
  }
  final repo = ref.watch(settingsRepositoryProvider);
  return _unwrapResult(repo.getGstConfig(companyId));
});

// ---------------------------------------------------------------------------
// User Preferences
// ---------------------------------------------------------------------------

/// Fetches user preferences from `/settings`.
final userPreferencesProvider = FutureProvider<UserPreferences>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return _unwrapResult(repo.getPreferences());
});

// ---------------------------------------------------------------------------
// Export Records
// ---------------------------------------------------------------------------

/// Fetches the export history for a company.
final exportRecordsProvider = FutureProvider.family<List<ExportRecord>, String>(
  (ref, companyId) async {
    final repo = ref.watch(settingsRepositoryProvider);
    return _unwrapResult(repo.getExportRecords(companyId));
  },
);

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Unwraps a [Result] future, throwing on failure.
Future<T> _unwrapResult<T>(Future<Result<T>> future) async {
  final result = await future;
  return switch (result) {
    Success<T>(:final value) => value,
    Failure<T>(:final error) => throw error,
    _ => throw const ApiError(message: 'Unexpected response.'),
  };
}
