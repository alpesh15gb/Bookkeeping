import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/local_database.dart';
import 'package:flutter_client/core/sync_manager.dart';
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
        await SyncManager.instance?.cacheGetResponse('/masters/products', data);
      } else {
        _errorMessage = 'Failed to load products';
      }
    } catch (e) {
      _errorMessage = 'An error occurred';
    }
    if (_products.isEmpty && !(SyncManager.instance?.isOnline ?? true)) {
      try {
        final cached = await LocalDatabase.query(
          'cached_products',
          where: 'tenant_id = ?',
          whereArgs: [ApiClient.tenantId],
        );
        _products = cached.map((row) {
          final jsonStr = row['json'] as String?;
          return ProductModel.fromJson(jsonStr != null ? jsonDecode(jsonStr) : row);
        }).toList();
        _errorMessage = _products.isNotEmpty ? null : 'No cached products available';
      } catch (_) {}
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addProduct(ProductModel product) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final body = jsonEncode(product.toJson());
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'create_product',
        endpoint: '${ApiClient.baseUrl}/masters/products',
        method: 'POST',
        body: body,
      );
      if (queued) {
        _products.add(product);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/masters/products'),
        body: body,
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
    final body = jsonEncode(product.toJson());
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'update_product',
        endpoint: '${ApiClient.baseUrl}/masters/products/$id',
        method: 'PUT',
        body: body,
      );
      if (queued) {
        final idx = _products.indexWhere((p) => p.id == id);
        if (idx >= 0) _products[idx] = product;
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/masters/products/$id'),
        body: body,
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
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'delete_product',
        endpoint: '${ApiClient.baseUrl}/masters/products/$id',
        method: 'DELETE',
      );
      if (queued) {
        _products.removeWhere((p) => p.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
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
