import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/auth.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  UserResponse? _currentUser;
  String? _errorMessage;
  List<TenantMembership> _memberships = [];
  String? _activeTenantId;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  UserResponse? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  List<TenantMembership> get memberships => _memberships;
  String? get activeTenantId => _activeTenantId;

  final ApiClient _client = ApiClient();

  AuthProvider() {
    restoreSession();
  }

  Future<void> restoreSession() async {
    _isLoading = true;
    notifyListeners();
    try {
      await ApiClient.initSession();
      if (!ApiClient.hasSavedSession) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      final response = await _client.get(
        Uri.parse('${ApiClient.baseUrl}/auth/me'),
      );
      if (response.statusCode == 200) {
        final respData = jsonDecode(response.body);
        _currentUser = UserResponse.fromJson(
          respData is Map<String, dynamic> ? respData : Map<String, dynamic>.from(respData is Map ? respData : {}),
        );
        _isAuthenticated = true;
        final memResponse = await _client.get(
          Uri.parse('${ApiClient.baseUrl}/auth/memberships'),
        );
        if (memResponse.statusCode == 200) {
          final memData = jsonDecode(memResponse.body);
          final List memItems = memData is Map ? (memData['items'] ?? []) : (memData is List ? memData : []);
          _memberships = memItems.map((e) => e is Map ? Map<String, dynamic>.from(e) : null).whereType<Map<String, dynamic>>().map((e) => TenantMembership.fromJson(e)).toList();
          _activeTenantId = ApiClient.tenantId;
          if (_activeTenantId == null && _memberships.isNotEmpty) {
            _activeTenantId = _memberships[0].tenantId;
            ApiClient.setTenantId(_activeTenantId);
          }
        }
      } else {
        await ApiClient.clearSession();
        _currentUser = null;
        _isAuthenticated = false;
        _memberships = [];
        _activeTenantId = null;
      }
    } catch (e) {
      // Network error during session restore — don't mark as authenticated
      // since we have no valid user data; show login screen instead
      await ApiClient.clearSession();
      _currentUser = null;
      _isAuthenticated = false;
      _memberships = [];
      _activeTenantId = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ApiClient.setAccessToken(data['access_token']);
        await ApiClient.saveRefreshToken(data['refresh_token']);

        // Fetch memberships to select default tenant ID
        final memResponse = await _client.get(
          Uri.parse('${ApiClient.baseUrl}/auth/memberships'),
        );
        if (memResponse.statusCode == 200) {
          final memData2 = jsonDecode(memResponse.body);
          final List memItems2 = memData2 is Map ? (memData2['items'] ?? []) : (memData2 is List ? memData2 : []);
          _memberships = memItems2.map((e) => e is Map ? Map<String, dynamic>.from(e) : null).whereType<Map<String, dynamic>>().map((e) => TenantMembership.fromJson(e)).toList();
          if (_memberships.isNotEmpty) {
            _activeTenantId = _memberships[0].tenantId;
            ApiClient.setTenantId(_activeTenantId);
          }
        }

        // Fetch user info
        final userResponse = await _client.get(
          Uri.parse('${ApiClient.baseUrl}/auth/me'),
        );
        if (userResponse.statusCode == 200) {
          final userData = jsonDecode(userResponse.body);
          _currentUser = UserResponse.fromJson(
            userData is Map<String, dynamic> ? userData : Map<String, dynamic>.from(userData is Map ? userData : {}),
          );
          _isAuthenticated = true;
          _isLoading = false;
          notifyListeners();
          return true;
        }
      } else {
        try {
          final errorData = jsonDecode(response.body);
          _errorMessage =
              errorData['detail'] ??
              'Login failed (HTTP ${response.statusCode})';
        } catch (_) {
          if (response.statusCode >= 500) {
            _errorMessage =
                'Server error (${response.statusCode}). Please try again later.';
          } else {
            _errorMessage = 'Login failed (HTTP ${response.statusCode})';
          }
        }
      }
    } catch (e) {
      _errorMessage = 'Connection error. Please check your network.';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    required String companyLegalName,
    String? companyGstin,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'full_name': fullName,
          'phone_number': phoneNumber,
          'company_legal_name': companyLegalName,
          'company_gstin': companyGstin,
        }),
      );

      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        _errorMessage = errorData['detail'] ?? 'Registration failed';
      }
    } catch (e) {
      _errorMessage = 'An error occurred. Please try again.';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/auth/change-password'),
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to change password';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> forgotPassword(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to send reset email';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> resetPassword(String token, String newPassword) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'new_password': newPassword}),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to reset password';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    try {
      await _client.post(Uri.parse('${ApiClient.baseUrl}/auth/logout'));
    } catch (_) {}
    await ApiClient.clearSession();
    _currentUser = null;
    _isAuthenticated = false;
    _memberships = [];
    _activeTenantId = null;
    notifyListeners();
  }

  void clearLocalSession() {
    _currentUser = null;
    _isAuthenticated = false;
    _memberships = [];
    _activeTenantId = null;
    notifyListeners();
  }

  Future<void> switchTenant(String tenantId) async {
    if (tenantId == _activeTenantId) return;
    _activeTenantId = tenantId;
    ApiClient.setTenantId(tenantId);
    notifyListeners();
  }
}
