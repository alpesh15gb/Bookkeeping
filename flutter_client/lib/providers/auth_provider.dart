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

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  UserResponse? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;

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
      // Try to fetch current user to verify session
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/auth/me'));
      if (response.statusCode == 200) {
        _currentUser = UserResponse.fromJson(jsonDecode(response.body));
        _isAuthenticated = true;
      } else {
        await ApiClient.clearSession();
      }
    } catch (_) {
      await ApiClient.clearSession();
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
        final memResponse = await _client.get(Uri.parse('${ApiClient.baseUrl}/auth/memberships'));
        if (memResponse.statusCode == 200) {
          final List memberships = jsonDecode(memResponse.body);
          if (memberships.isNotEmpty) {
            ApiClient.setTenantId(memberships[0]['tenant_id']);
          }
        }

        // Fetch user info
        final userResponse = await _client.get(Uri.parse('${ApiClient.baseUrl}/auth/me'));
        if (userResponse.statusCode == 200) {
          _currentUser = UserResponse.fromJson(jsonDecode(userResponse.body));
          _isAuthenticated = true;
          _isLoading = false;
          notifyListeners();
          return true;
        }
      } else {
        final errorData = jsonDecode(response.body);
        _errorMessage = errorData['detail'] ?? 'Login failed';
      }
    } catch (e) {
      _errorMessage = 'An error occurred. Please try again.';
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

  Future<bool> changePassword(String currentPassword, String newPassword) async {
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
    notifyListeners();
  }
}
