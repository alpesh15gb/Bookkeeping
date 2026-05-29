import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class MiscProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  // GSTR-2A
  Future<bool> uploadGstr2a(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/gst/gstr2a/upload'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to upload GSTR-2A';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Audit Trail
  Future<Map<String, dynamic>?> fetchAuditLogs({int page = 1, int limit = 50}) async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiClient.baseUrl}/audit-logs?page=$page&limit=$limit'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  // Reminders
  Future<List<dynamic>> fetchReminders() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reminders'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List;
      }
    } catch (_) {}
    return [];
  }

  Future<bool> createReminder(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/reminders'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create reminder';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Vyapar Import
  Future<Map<String, dynamic>?> importVyapar(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/import/vyapar'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return jsonDecode(response.body);
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to import Vyapar data';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return null;
  }
}
