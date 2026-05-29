import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class BankingProfileProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _profiles = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<dynamic> get profiles => _profiles;

  final ApiClient _client = ApiClient();

  Future<void> fetchBankingProfiles() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/banking-profiles'));
      if (response.statusCode == 200) {
        _profiles = jsonDecode(response.body) as List;
      } else {
        _errorMessage = 'Failed to load banking profiles';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getBankingProfile(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/banking-profiles/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> createBankingProfile(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/masters/banking-profiles'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchBankingProfiles();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create banking profile';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateBankingProfile(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/masters/banking-profiles/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchBankingProfiles();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update banking profile';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteBankingProfile(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(Uri.parse('${ApiClient.baseUrl}/masters/banking-profiles/$id'));
      if (response.statusCode == 204) {
        await fetchBankingProfiles();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to delete banking profile';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
}
