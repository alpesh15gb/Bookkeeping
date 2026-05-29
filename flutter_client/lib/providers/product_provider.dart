import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/product.dart';

class ProductProvider extends ChangeNotifier {
  List<ProductModel> _products = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<ProductModel> get products => _products;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  Future<void> fetchProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/products'));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        _products = data.map((x) => ProductModel.fromJson(x)).toList();
      } else {
        _errorMessage = 'Failed to load products';
      }
    } catch (e) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addProduct(ProductModel product) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/masters/products'),
        body: jsonEncode(product.toJson()),
      );
      debugPrint('Add product response status: ${response.statusCode}');
      debugPrint('Add product response body: ${response.body}');
      if (response.statusCode == 201) {
        await fetchProducts();
        return true;
      } else {
        _errorMessage = ApiClient.parseError(response.body, fallback: 'Failed to add product');
      }
    } catch (e, stack) {
      debugPrint('Exception in addProduct: $e\n$stack');
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> updateProduct(String id, ProductModel product) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/masters/products/$id'),
        body: jsonEncode(product.toJson()),
      );
      if (response.statusCode == 200) {
        await fetchProducts();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to update product';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> deleteProduct(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(Uri.parse('${ApiClient.baseUrl}/masters/products/$id'));
      if (response.statusCode == 204) {
        await fetchProducts();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to delete product';
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
