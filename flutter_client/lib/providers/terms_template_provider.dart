import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/terms_template.dart';
import 'package:http/http.dart' as http;

class TermsTemplateProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final http.Client _client;

  TermsTemplateProvider({http.Client? client}) : _client = client ?? ApiClient();

  Uri _buildUri(String endpoint) {
    final queryParams = <String>[];
    ApiClient.fyParams.forEach((k, v) {
      queryParams.add('$k=$v');
    });
    if (queryParams.isEmpty) return Uri.parse(endpoint);
    final separator = endpoint.contains('?') ? '&' : '?';
    return Uri.parse('$endpoint$separator${queryParams.join('&')}');
  }

  List<TermsTemplateModel> _items = [];
  List<TermsTemplateModel> get items => _items;

  Future<List<TermsTemplateModel>> fetchTemplates() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final templatesResponse = await _client.get(_buildUri('${ApiClient.baseUrl}/terms-templates'));
      if (templatesResponse.statusCode == 200) {
        final data = jsonDecode(templatesResponse.body);
        final list = data is List ? data : [];
        final templates = list.map((e) => TermsTemplateModel.fromJson(e)).toList();

        final hasBackendPresets = templates.any((t) => t.isPreset);
        if (!hasBackendPresets) {
          final presetsResponse = await _client.get(Uri.parse('${ApiClient.baseUrl}/terms-templates/presets'));
          if (presetsResponse.statusCode == 200) {
            final presetsData = jsonDecode(presetsResponse.body);
            final presets = presetsData is List ? presetsData : [];
            templates.addAll(
              presets
                  .asMap()
                  .entries
                  .map((e) => TermsTemplateModel.presetFromJson(
                        Map<String, dynamic>.from(e.value),
                        e.key,
                      )),
            );
          }
        }

        _items = templates;
        _isLoading = false;
        notifyListeners();
        return _items;
      }
      _errorMessage = 'Failed to load templates';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createTemplate(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/terms-templates'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateTemplate(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        _buildUri('${ApiClient.baseUrl}/terms-templates/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteTemplate(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(
        Uri.parse('${ApiClient.baseUrl}/terms-templates/$id'),
      );
      if (response.statusCode == 204 || response.statusCode == 200) {
        _items.removeWhere((e) => e.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to delete';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
}
