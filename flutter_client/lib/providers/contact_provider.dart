import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/contact.dart';

class ContactProvider extends ChangeNotifier {
  List<ContactModel> _contacts = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<ContactModel> get contacts => _contacts;
  List<ContactModel> get customers => _contacts.where((c) => c.contactType == 'CUSTOMER' || c.contactType == 'BOTH').toList();
  List<ContactModel> get vendors => _contacts.where((c) => c.contactType == 'VENDOR' || c.contactType == 'BOTH').toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  Future<void> fetchContacts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/contacts'));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        _contacts = data.map((x) => ContactModel.fromJson(x)).toList();
      } else {
        _errorMessage = 'Failed to load contacts';
      }
    } catch (e) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addContact(ContactModel contact) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/masters/contacts'),
        body: jsonEncode(contact.toJson()),
      );
      debugPrint('Add contact response status: ${response.statusCode}');
      debugPrint('Add contact response body: ${response.body}');
      if (response.statusCode == 201) {
        await fetchContacts();
        return true;
      } else {
        _errorMessage = ApiClient.parseError(response.body, fallback: 'Failed to create contact');
      }
    } catch (e, stack) {
      debugPrint('Exception in addContact: $e\n$stack');
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> updateContact(String id, ContactModel contact) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/masters/contacts/$id'),
        body: jsonEncode(contact.toJson()),
      );
      if (response.statusCode == 200) {
        await fetchContacts();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to update contact';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> deleteContact(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(Uri.parse('${ApiClient.baseUrl}/masters/contacts/$id'));
      if (response.statusCode == 204) {
        await fetchContacts();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to delete contact';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }
}
