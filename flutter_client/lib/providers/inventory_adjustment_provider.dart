import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class InventoryAdjustmentProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _adjustments = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<dynamic> get adjustments => _adjustments;

  final ApiClient _client = ApiClient();

  Future<void> fetchAdjustments() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/inventory-adjustments'));
      if (response.statusCode == 200) {
        _adjustments = jsonDecode(response.body) as List;
      } else {
        _errorMessage = 'Failed to load inventory adjustments';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> fetchAdjustmentDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/inventory-adjustments/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> createAdjustment(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/inventory-adjustments'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchAdjustments();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create adjustment';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateAdjustment(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/inventory-adjustments/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchAdjustments();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update adjustment';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> confirmAdjustment(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/inventory-adjustments/$id/confirm'));
      if (response.statusCode == 200) {
        await fetchAdjustments();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to confirm adjustment';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> cancelAdjustment(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/inventory-adjustments/$id/cancel'));
      if (response.statusCode == 200) {
        await fetchAdjustments();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to cancel adjustment';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
}
