import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class EwayBillProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _ewayBills = [];
  List<dynamic> _einvoices = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<dynamic> get ewayBills => _ewayBills;
  List<dynamic> get einvoices => _einvoices;

  final ApiClient _client = ApiClient();

  Future<void> fetchEwayBills() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/eway-bills'));
      if (response.statusCode == 200) {
        _ewayBills = jsonDecode(response.body) as List;
      } else {
        _errorMessage = 'Failed to load e-way bills';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> fetchEwayBillDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/eway-bills/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> generateEwayBill(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/eway-bills'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchEwayBills();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to generate e-way bill';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> cancelEwayBill(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/eway-bills/$id/cancel'));
      if (response.statusCode == 200) {
        await fetchEwayBills();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to cancel e-way bill';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateVehicle(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/eway-bills/$id/vehicle'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update vehicle';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> generateConsolidated(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/eway-bills/consolidated'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to generate consolidated e-way bill';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // HSN Lookup
  Future<Map<String, dynamic>?> lookupHsn(String hsnCode) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/gst/hsn/${Uri.encodeComponent(hsnCode)}'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  // GSTIN Verification
  Future<Map<String, dynamic>?> fetchGstCaptcha() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/gst/verify/captcha'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> verifyGstin(String gstin, String captcha) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/gst/verify'),
        body: jsonEncode({'gstin': gstin, 'captcha': captcha}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
