import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_client/core/api_client.dart';

/// Financial year status from the backend.
enum FYStatus {
  current, upcoming, readyToClose, locked, archived, unknown;

  factory FYStatus.fromString(String s) {
    switch (s.toUpperCase()) {
      case 'CURRENT': return FYStatus.current;
      case 'UPCOMING': return FYStatus.upcoming;
      case 'READY_TO_CLOSE': return FYStatus.readyToClose;
      case 'LOCKED': return FYStatus.locked;
      case 'ARCHIVED': return FYStatus.archived;
      default: return FYStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case FYStatus.current: return 'Current';
      case FYStatus.upcoming: return 'Upcoming';
      case FYStatus.readyToClose: return 'Ready to Close';
      case FYStatus.locked: return 'Locked';
      case FYStatus.archived: return 'Archived';
      case FYStatus.unknown: return 'Unknown';
    }
  }

  Color get color {
    switch (this) {
      case FYStatus.current: return const Color(0xFF175CD3);
      case FYStatus.upcoming: return const Color(0xFF475467);
      case FYStatus.readyToClose: return const Color(0xFFD97706);
      case FYStatus.locked: return const Color(0xFF6B7280);
      case FYStatus.archived: return const Color(0xFF9CA1AB);
      case FYStatus.unknown: return const Color(0xFF9CA1AB);
    }
  }

  Color get bgColor {
    switch (this) {
      case FYStatus.current: return const Color(0xFFEFF6FF);
      case FYStatus.upcoming: return const Color(0xFFF2F4F7);
      case FYStatus.readyToClose: return const Color(0xFFFFFBEB);
      case FYStatus.locked: return const Color(0xFFF2F2F4);
      case FYStatus.archived: return const Color(0xFFF2F2F4);
      case FYStatus.unknown: return const Color(0xFFF2F2F4);
    }
  }
}

/// Represents a financial year from the backend.
class FinancialYear {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final FYStatus status;
  final bool isCurrent;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime? reopenedAt;
  final String? reopenedBy;
  final String? reopenReason;
  final String? journalEntryId;
  final int transactionCount;
  final String? createdBy;
  final String? switchedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FinancialYear({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.isCurrent,
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
    this.reopenReason,
    this.journalEntryId,
    this.transactionCount = 0,
    this.createdBy,
    this.switchedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  String get label => name;

  String get fullLabel => 'FY $name';

  String get dateRange =>
      '${startDate.day}/${startDate.month}/${startDate.year} – ${endDate.day}/${endDate.month}/${endDate.year}';

  bool get isClosedOrLocked => status == FYStatus.locked;

  bool get canEdit => !isClosedOrLocked;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start_date': startDate.toIso8601String().substring(0, 10),
    'end_date': endDate.toIso8601String().substring(0, 10),
    'status': status.name.toUpperCase(),
    'is_current': isCurrent,
    'transaction_count': transactionCount,
  };

  factory FinancialYear.fromJson(Map<String, dynamic> json) {
    return FinancialYear(
      id: json['id'] as String,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      status: FYStatus.fromString(json['status'] as String? ?? 'CURRENT'),
      isCurrent: json['is_current'] == true,
      closedAt: json['closed_at'] != null ? DateTime.tryParse(json['closed_at'] as String) : null,
      closedBy: json['closed_by'] as String?,
      reopenedAt: json['reopened_at'] != null ? DateTime.tryParse(json['reopened_at'] as String) : null,
      reopenedBy: json['reopened_by'] as String?,
      reopenReason: json['reopen_reason'] as String?,
      journalEntryId: json['journal_entry_id'] as String?,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      createdBy: json['created_by'] as String?,
      switchedBy: json['switched_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Year-end dashboard data from the backend.
class YearEndDashboard {
  final FinancialYear financialYear;
  final int readinessScore;
  final bool trialBalanceBalanced;
  final int unpostedDocumentsCount;
  final List<Map<String, dynamic>> unpostedDocuments;
  final double netProfit;
  final bool closingAllowed;
  final List<String> blockingItems;

  const YearEndDashboard({
    required this.financialYear,
    required this.readinessScore,
    required this.trialBalanceBalanced,
    required this.unpostedDocumentsCount,
    required this.unpostedDocuments,
    required this.netProfit,
    required this.closingAllowed,
    required this.blockingItems,
  });

  factory YearEndDashboard.fromJson(Map<String, dynamic> json) {
    return YearEndDashboard(
      financialYear: FinancialYear.fromJson(json['financial_year'] as Map<String, dynamic>),
      readinessScore: (json['readiness_score'] as num?)?.toInt() ?? 0,
      trialBalanceBalanced: json['trial_balance_balanced'] == true,
      unpostedDocumentsCount: (json['unposted_documents_count'] as num?)?.toInt() ?? 0,
      unpostedDocuments: (json['unposted_documents'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [],
      netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0.0,
      closingAllowed: json['closing_allowed'] == true,
      blockingItems: (json['blocking_items'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
    );
  }
}

class FinancialYearProvider extends ChangeNotifier {
  FinancialYear? _activeYear;
  List<FinancialYear> _availableYears = [];
  bool _isLoading = false;
  String? _errorMessage;
  YearEndDashboard? _dashboard;
  String? _pendingFySwitch; // Track pending FY switch for offline sync

  FinancialYear? get activeYear => _activeYear;
  List<FinancialYear> get availableYears => _availableYears;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  YearEndDashboard? get dashboard => _dashboard;

  static const _prefsKey = 'active_fy_id';

  final ApiClient _client = ApiClient();

  Future<void> init() async {
    await _loadYears();
  }

  Future<void> _loadYears() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _client.get(
        Uri.parse('${ApiClient.baseUrl}/financial-years'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        _availableYears = data
            .map((e) => FinancialYear.fromJson(e as Map<String, dynamic>))
            .toList();

        // Restore saved active year
        final prefs = await SharedPreferences.getInstance();
        final savedId = prefs.getString(_prefsKey);

        if (savedId != null) {
          _activeYear = _availableYears.firstWhere(
            (y) => y.id == savedId,
            orElse: () => _availableYears.firstWhere(
              (y) => y.isCurrent,
              orElse: () => _availableYears.first,
            ),
          );
        } else {
          final currentFY = _availableYears.where((y) => y.isCurrent).firstOrNull;
          _activeYear = currentFY ?? (_availableYears.isNotEmpty ? _availableYears.first : null);
        }

        ApiClient.setFYParams(activeDateRangeParams);

        // If backend returned empty list, fall back to local generation
        if (_availableYears.isEmpty) {
          await _loadYearsLocal();
        }
      } else if (response.statusCode == 404) {
        // No financial years exist yet — fall back to local generation
        await _loadYearsLocal();
      }
    } catch (_) {
      await _loadYearsLocal();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fallback: generate FYs locally when backend has no FY records yet.
  Future<void> _loadYearsLocal() async {
    int earliestYear = DateTime.now().year - 5;
    try {
      final tenantId = ApiClient.tenantId;
      if (tenantId != null) {
        final res = await _client.get(
          Uri.parse('${ApiClient.baseUrl}/companies/$tenantId'),
        );
        if (res.statusCode == 200) {
          final company = jsonDecode(res.body) as Map<String, dynamic>;
          final createdAt = company['created_at']?.toString();
          if (createdAt != null) {
            final dt = DateTime.tryParse(createdAt);
            if (dt != null) earliestYear = dt.year;
          }
        }
      }
    } catch (_) {}

    final currentYear = DateTime.now().year;
    final now = DateTime.now();
    final currentFYStart = now.month >= 4 ? now.year : now.year - 1;

    _availableYears = [];
    for (var y = currentYear + 1; y >= earliestYear; y--) {
        _availableYears.add(FinancialYear(
          id: 'local-$y',
          name: '$y-${((y + 1) % 100).toString().padLeft(2, '0')}',
          startDate: DateTime(y, 4, 1),
          endDate: DateTime(y + 1, 3, 31),
          status: y == currentFYStart ? FYStatus.current : (y < currentFYStart ? FYStatus.locked : FYStatus.upcoming),
          isCurrent: y == currentFYStart,
          transactionCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }

    _activeYear = _availableYears.where((y) => y.isCurrent).firstOrNull ?? 
        (_availableYears.isNotEmpty ? _availableYears.first : null);

    ApiClient.setFYParams(activeDateRangeParams);
  }

  Future<void> setActiveYear(FinancialYear year) async {
    if (_activeYear?.id == year.id) return;

    // Try backend switch
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/financial-years/switch'),
        body: jsonEncode({'financial_year_id': year.id}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final switched = FinancialYear.fromJson(data);
        _activeYear = switched;
        // Update in list
        final idx = _availableYears.indexWhere((y) => y.id == switched.id);
        if (idx >= 0) _availableYears[idx] = switched;
      } else {
        // Server rejected — don't update locally
        return;
      }
    } catch (_) {
      // Offline — queue the switch for later, don't diverge client from server
      _pendingFySwitch = year.id;
      _activeYear = year;
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _activeYear!.id);
    ApiClient.setFYParams(activeDateRangeParams);
    await _loadYears();
  }

  Map<String, String> get activeDateRangeParams {
    if (_activeYear == null) return {};
    final s = _activeYear!.startDate;
    final e = _activeYear!.endDate;
    return {
      'date_from': '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}',
      'date_to': '${e.year}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}',
    };
  }

  bool get isViewingHistoricalYear {
    return _activeYear?.isClosedOrLocked == true && !(_activeYear?.isCurrent ?? true);
  }

  bool get isCurrentFY {
    return _activeYear?.isCurrent ?? false;
  }

  /// Create a new financial year.
  Future<FinancialYear?> createFinancialYear({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/financial-years'),
        body: jsonEncode({
          'name': name,
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate.toIso8601String().substring(0, 10),
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fy = FinancialYear.fromJson(data);
        _availableYears.insert(0, fy);
        _isLoading = false;
        notifyListeners();
        return fy;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to create financial year';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return null;
  }

  /// Load year-end dashboard for a specific FY.
  Future<YearEndDashboard?> loadDashboard(String fyId) async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiClient.baseUrl}/financial-years/$fyId/dashboard'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _dashboard = YearEndDashboard.fromJson(data);
        notifyListeners();
        return _dashboard;
      }
    } catch (_) {}
    return null;
  }

  /// Close a financial year via the backend.
  Future<Map<String, dynamic>?> closeFinancialYear(String fyId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/financial-years/$fyId/close'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Clear saved FY preference — the old one is now LOCKED
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
        await _loadYears();
        // If _loadYears didn't pick the new current FY, find it manually
        if (_activeYear == null || _activeYear!.status == FYStatus.locked) {
          _activeYear = _availableYears.firstWhere(
            (y) => y.isCurrent,
            orElse: () => _availableYears.isNotEmpty ? _availableYears.first : _activeYear!,
          );
          ApiClient.setFYParams(activeDateRangeParams);
        }
        _isLoading = false;
        notifyListeners();
        return data;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to close financial year';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return null;
  }

  /// Refresh from backend.
  Future<void> refresh() async {
    await _loadYears();
  }
}
