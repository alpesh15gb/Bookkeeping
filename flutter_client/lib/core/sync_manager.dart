import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/local_database.dart';

class SyncManager extends ChangeNotifier {
  static SyncManager? _instance;
  static SyncManager? get instance => _instance;

  bool _isOnline = true;
  bool _isSyncing = false;
  String? _lastSyncMessage;
  int _pendingCount = 0;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  String? get lastSyncMessage => _lastSyncMessage;
  int get pendingCount => _pendingCount;

  StreamSubscription? _connectivitySub;

  SyncManager() {
    _instance = this;
    _init();
  }

  Future<void> _init() async {
    // Check initial connectivity
    final result = await Connectivity().checkConnectivity();
    _updateConnectivity(result);

    // Listen for changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      _updateConnectivity(result);
    });

    // Count pending actions
    await _refreshPendingCount();
  }

  void _updateConnectivity(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (!wasOnline && _isOnline) {
      // Just came back online — trigger sync
      _lastSyncMessage = 'Connection restored. Syncing...';
      notifyListeners();
      syncPendingActions();
    } else if (wasOnline && !_isOnline) {
      _lastSyncMessage = 'Working offline. Changes will sync when connection returns.';
      notifyListeners();
    }
  }

  Future<void> _refreshPendingCount() async {
    final pending = await LocalDatabase.getPendingActions();
    _pendingCount = pending.length;
    notifyListeners();
  }

  /// Call this after any successful API GET to cache the response locally
  Future<void> cacheGetResponse(
    String endpoint,
    List<dynamic> data, {
    String? tenantId,
  }) async {
    final tId = tenantId ?? ApiClient.tenantId;
    if (tId == null) return;

    if (endpoint.contains('/masters/contacts')) {
      await LocalDatabase.cacheContacts(tId, data);
    } else if (endpoint.contains('/masters/products')) {
      await LocalDatabase.cacheProducts(tId, data);
    } else if (endpoint.contains('/invoices') && !endpoint.contains('/invoices/')) {
      await LocalDatabase.cacheInvoices(tId, data);
    } else if (endpoint.contains('/bills') && !endpoint.contains('/bills/')) {
      await LocalDatabase.cacheBills(tId, data);
    } else if (endpoint.contains('/expenses') && !endpoint.contains('/expenses/')) {
      await LocalDatabase.cacheExpenses(tId, data);
    }
  }

  /// Call this after any successful API GET for a single document
  Future<void> cacheDocumentDetail(
    String endpoint,
    Map<String, dynamic> data, {
    String? tenantId,
  }) async {
    final tId = tenantId ?? ApiClient.tenantId;
    if (tId == null || data['id'] == null) return;

    String docType = 'unknown';
    if (endpoint.contains('/invoices/')) docType = 'invoice';
    else if (endpoint.contains('/bills/')) docType = 'bill';
    else if (endpoint.contains('/expenses/')) docType = 'expense';

    await LocalDatabase.cacheDocumentDetail(
      tId,
      docType,
      data['id'].toString(),
      data,
    );
  }

  /// Enqueue a write action when offline, or return null if online (caller should proceed normally)
  Future<bool> handleWrite({
    required String action,
    required String endpoint,
    required String method,
    String? body,
    String? headers,
  }) async {
    if (_isOnline) {
      return false; // Not queued — proceed with normal API call
    }

    await LocalDatabase.enqueueAction(
      action: action,
      endpoint: endpoint,
      method: method,
      body: body,
      headers: headers,
    );
    await _refreshPendingCount();
    _lastSyncMessage = '$action queued for sync.';
    notifyListeners();
    return true; // Was queued
  }

  /// Sync all pending actions when back online
  Future<void> syncPendingActions() async {
    if (!_isOnline || _isSyncing) return;

    _isSyncing = true;
    notifyListeners();

    final pending = await LocalDatabase.getPendingActions();
    int successCount = 0;
    int failCount = 0;

    for (final action in pending) {
      final id = action['id'] as int;
      final endpoint = action['endpoint'] as String;
      final method = action['method'] as String;
      final body = action['body'] as String?;
      final retryCount = action['retry_count'] as int? ?? 0;

      // Skip actions that have exceeded max retries
      if (retryCount >= 5) {
        _lastSyncMessage = 'Some actions failed after 5 retries. Please try manually.';
        continue;
      }

      try {
        final uri = Uri.parse(endpoint);
        http.Response response;

        switch (method.toUpperCase()) {
          case 'POST':
            response = await ApiClient().post(
              uri,
              body: body,
              headers: {'Content-Type': 'application/json'},
            );
            break;
          case 'PUT':
            response = await ApiClient().put(
              uri,
              body: body,
              headers: {'Content-Type': 'application/json'},
            );
            break;
          case 'DELETE':
            response = await ApiClient().delete(uri);
            break;
          default:
            continue;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await LocalDatabase.removePendingAction(id);
          successCount++;
        } else if (response.statusCode == 0) {
          // Network error — stop syncing, wait for connectivity change
          _lastSyncMessage = 'Network error. Will retry when connected.';
          break;
        } else {
          await LocalDatabase.incrementRetry(id, 'HTTP ${response.statusCode}');
          failCount++;
        }
      } catch (e) {
        await LocalDatabase.incrementRetry(id, e.toString());
        failCount++;
      }
    }

    await _refreshPendingCount();
    _isSyncing = false;

    if (successCount > 0 && failCount == 0) {
      _lastSyncMessage = '$successCount items synced successfully.';
    } else if (successCount > 0 && failCount > 0) {
      _lastSyncMessage = '$successCount synced, $failCount failed.';
    } else if (failCount > 0) {
      _lastSyncMessage = '$failCount items failed to sync. Will retry.';
    } else {
      _lastSyncMessage = null;
    }
    notifyListeners();
  }

  /// Force a full sync of all master data
  Future<void> fullSync() async {
    if (!_isOnline) {
      _lastSyncMessage = 'Cannot sync — offline.';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      // Sync contacts
      final contactsResp = await ApiClient().get(
        Uri.parse('${ApiClient.baseUrl}/masters/contacts'),
      );
      if (contactsResp.statusCode == 200) {
        final contacts = jsonDecode(contactsResp.body);
        if (contacts is List) {
          await LocalDatabase.cacheContacts(ApiClient.tenantId ?? '', contacts);
        }
      }

      // Sync products
      final productsResp = await ApiClient().get(
        Uri.parse('${ApiClient.baseUrl}/masters/products'),
      );
      if (productsResp.statusCode == 200) {
        final products = jsonDecode(productsResp.body);
        if (products is List) {
          await LocalDatabase.cacheProducts(ApiClient.tenantId ?? '', products);
        }
      }

      _lastSyncMessage = 'Full sync completed.';
    } catch (e) {
      _lastSyncMessage = 'Sync failed: $e';
    }

    _isSyncing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
