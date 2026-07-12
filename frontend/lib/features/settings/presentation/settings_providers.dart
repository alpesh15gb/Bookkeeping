/// Shared providers for Settings screens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../auth/data/models/membership_models.dart';
import '../data/models/financial_year.dart';
import '../data/models/team_member.dart';
import '../data/settings_repository.dart';

/// Provider for [SettingsRepository].
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(apiClientProvider));
});

/// Fetches the full Company profile by ID.
final companyProfileProvider =
    FutureProvider.family<Company, String>((ref, id) async {
  final repo = ref.watch(settingsRepositoryProvider);
  final result = await repo.getCompany(id);
  return switch (result) {
    Success<Company>(:final value) => value,
    Failure<Company>(:final error) => throw error,
    _ => throw const ApiError(message: 'Unexpected response.'),
  };
});

/// Fetches the list of FinancialYears for a company.
final financialYearListProvider =
    FutureProvider.family<List<FinancialYear>, String>(
        (ref, companyId) async {
  final repo = ref.watch(settingsRepositoryProvider);
  final result = await repo.getFinancialYears(companyId);
  return switch (result) {
    Success<List<FinancialYear>>(:final value) => value,
    Failure<List<FinancialYear>>(:final error) => throw error,
    _ => throw const ApiError(message: 'Unexpected response.'),
  };
});

/// Fetches the list of TeamMembers for a company.
final teamMemberListProvider =
    FutureProvider.family<List<TeamMember>, String>((ref, companyId) async {
  final repo = ref.watch(settingsRepositoryProvider);
  final result = await repo.getTeamMembers(companyId);
  return switch (result) {
    Success<List<TeamMember>>(:final value) => value,
    Failure<List<TeamMember>>(:final error) => throw error,
    _ => throw const ApiError(message: 'Unexpected response.'),
  };
});
