import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class SettingsProvider extends ChangeNotifier {
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _company = {};
  List<dynamic> _numberingSeries = [];
  List<dynamic> _branches = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  Map<String, dynamic> get settings => _settings;
  Map<String, dynamic> get company => _company;
  List<dynamic> get numberingSeries => _numberingSeries;
  List<dynamic> get branches => _branches;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  Future<void> fetchAllSettings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final tenantId = ApiClient.tenantId;
      if (tenantId == null) {
        _errorMessage = 'No active company found. Please log in again.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final results = await Future.wait([
        _client.get(Uri.parse('${ApiClient.baseUrl}/settings')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/companies/$tenantId')),
      ]);

      final settingsRes = results[0];
      final companyRes = results[1];

      if (settingsRes.statusCode == 200) {
        _settings = jsonDecode(settingsRes.body) as Map<String, dynamic>;
      }
      if (companyRes.statusCode == 200) {
        _company = jsonDecode(companyRes.body) as Map<String, dynamic>;
      }

      await fetchNumberingSeries();
      await fetchBranches();
    } catch (e) {
      _errorMessage = 'Failed to load settings';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveSettings({
    required Map<String, dynamic> companyPayload,
    required Map<String, dynamic> settingsPayload,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final tenantId = _company['id'] ?? ApiClient.tenantId;
      if (tenantId != null && companyPayload.isNotEmpty) {
        final companyRes = await _client.put(
          Uri.parse('${ApiClient.baseUrl}/companies/$tenantId'),
          body: jsonEncode(companyPayload),
        );
        if (companyRes.statusCode != 200) {
          final data = jsonDecode(companyRes.body);
          _errorMessage = data['detail'] ?? 'Failed to update company info';
          _isSaving = false;
          notifyListeners();
          return false;
        }
      }

      if (settingsPayload.isNotEmpty) {
        final settingsRes = await _client.put(
          Uri.parse('${ApiClient.baseUrl}/settings'),
          body: jsonEncode(settingsPayload),
        );
        if (settingsRes.statusCode != 200) {
          final data = jsonDecode(settingsRes.body);
          _errorMessage = data['detail'] ?? 'Failed to update settings';
          _isSaving = false;
          notifyListeners();
          return false;
        }
      }

      await fetchAllSettings();
      return true;
    } catch (_) {
      _errorMessage = 'Failed to save settings';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
    return false;
  }

  Future<void> fetchNumberingSeries() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/settings/series'));
      if (response.statusCode == 200) {
        _numberingSeries = jsonDecode(response.body) as List;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> createNumberingSeries(Map<String, dynamic> payload) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/settings/series'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchNumberingSeries();
        _isSaving = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create numbering series';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isSaving = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateNumberingSeries(String id, Map<String, dynamic> payload) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/settings/series/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchNumberingSeries();
        _isSaving = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update numbering series';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isSaving = false;
    notifyListeners();
    return false;
  }

  Future<void> fetchBranches() async {
    final tenantId = _company['id'] ?? ApiClient.tenantId;
    if (tenantId == null) return;
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/companies/$tenantId/branches'));
      if (response.statusCode == 200) {
        _branches = jsonDecode(response.body) as List;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> createBranch(Map<String, dynamic> payload) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final tenantId = _company['id'] ?? ApiClient.tenantId;
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/companies/$tenantId/branches'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchBranches();
        _isSaving = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create branch';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isSaving = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateBranch(String branchId, Map<String, dynamic> payload) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final tenantId = _company['id'] ?? ApiClient.tenantId;
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/companies/$tenantId/branches/$branchId'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchBranches();
        _isSaving = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update branch';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isSaving = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteBranch(String branchId) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final tenantId = _company['id'] ?? ApiClient.tenantId;
      final response = await _client.delete(Uri.parse('${ApiClient.baseUrl}/companies/$tenantId/branches/$branchId'));
      if (response.statusCode == 204) {
        await fetchBranches();
        _isSaving = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to delete branch';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isSaving = false;
    notifyListeners();
    return false;
  }
}
