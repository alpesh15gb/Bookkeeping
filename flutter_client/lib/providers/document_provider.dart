import 'dart:convert';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class DocumentProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  // 1. Estimates (Proforma Invoices)
  Future<List<dynamic>> fetchEstimates() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/proforma-invoices'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createEstimate(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/proforma-invoices'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<Map<String, dynamic>?> previewEstimate(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/proforma-invoices/preview'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  // 2. Expenses
  Future<List<dynamic>> fetchExpenses() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/expenses'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createExpense(Map<String, dynamic> payload) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/expenses'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // 3. Credit Notes
  Future<List<dynamic>> fetchCreditNotes() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createCreditNote(Map<String, dynamic> payload) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<Map<String, dynamic>?> previewCreditNote(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes/preview'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  // 4. Debit Notes
  Future<List<dynamic>> fetchDebitNotes() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createDebitNote(Map<String, dynamic> payload) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<Map<String, dynamic>?> previewDebitNote(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes/preview'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  // 5. Purchase Orders
  Future<List<dynamic>> fetchPurchaseOrders() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/purchase-orders'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createPurchaseOrder(Map<String, dynamic> payload) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/purchase-orders'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // 6. Sales Orders
  Future<List<dynamic>> fetchSalesOrders() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales-orders'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createSalesOrder(Map<String, dynamic> payload) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/sales-orders'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Convert/Issue methods
  Future<bool> issueEstimate(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/proforma-invoices/$id/issue'),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to issue estimate';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> convertEstimate(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/proforma-invoices/$id/convert'),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to convert estimate';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Cancel methods (POST-based, for documents with ledger impact)
  Future<bool> cancelEstimate(String id) async {
    return _cancel('${ApiClient.baseUrl}/proforma-invoices/$id/cancel');
  }

  Future<bool> deleteExpense(String id) async {
    return _delete('${ApiClient.baseUrl}/expenses/$id');
  }

  Future<bool> cancelExpense(String id) async {
    return _cancel('${ApiClient.baseUrl}/expenses/$id/cancel');
  }

  Future<bool> postExpense(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/expenses/$id/post'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to post expense';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> cancelCreditNote(String id) async {
    return _cancel('${ApiClient.baseUrl}/invoices/credit-notes/$id/cancel');
  }

  Future<bool> cancelDebitNote(String id) async {
    return _cancel('${ApiClient.baseUrl}/invoices/debit-notes/$id/cancel');
  }

  Future<bool> cancelPurchaseOrder(String id) async {
    return _cancel('${ApiClient.baseUrl}/purchase-orders/$id/cancel');
  }

  Future<bool> confirmPurchaseOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/purchase-orders/$id/confirm');
  }

  Future<bool> receivePurchaseOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/purchase-orders/$id/receive');
  }

  Future<bool> cancelSalesOrder(String id) async {
    return _cancel('${ApiClient.baseUrl}/sales-orders/$id/cancel');
  }

  Future<bool> convertSalesOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/sales-orders/$id/convert');
  }

  Future<bool> confirmSalesOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/sales-orders/$id/confirm');
  }

  Future<bool> deliverSalesOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/sales-orders/$id/deliver');
  }

  // Backward compatibility
  Future<bool> deleteEstimate(String id) async => _delete('${ApiClient.baseUrl}/proforma-invoices/$id');
  Future<bool> deleteCreditNote(String id) async => _delete('${ApiClient.baseUrl}/invoices/credit-notes/$id');
  Future<bool> deleteDebitNote(String id) async => _delete('${ApiClient.baseUrl}/invoices/debit-notes/$id');
  Future<bool> deletePurchaseOrder(String id) async => cancelPurchaseOrder(id);
  Future<bool> deleteSalesOrder(String id) async => cancelSalesOrder(id);

  Future<Map<String, dynamic>?> fetchEstimateDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/proforma-invoices/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchPurchaseOrderDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/purchase-orders/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchSalesOrderDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales-orders/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchExpenseDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/expenses/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> updateEstimate(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/proforma-invoices/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update estimate';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updatePurchaseOrder(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/purchase-orders/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update purchase order';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateSalesOrder(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/sales-orders/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update sales order';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateExpense(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/expenses/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update expense';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  List<dynamic> _expenseCategories = [];
  List<dynamic> get expenseCategories => _expenseCategories;
  List<dynamic> get taxTemplates => _taxTemplates;
  List<dynamic> get paymentTerms => _paymentTerms;

  Future<void> fetchExpenseCategories() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/expense-categories'));
      if (response.statusCode == 200) {
        _expenseCategories = jsonDecode(response.body);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> createExpenseCategory(String name) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/masters/expense-categories'),
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 201) {
        await fetchExpenseCategories();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> previewExpense(double amount, double gstRate) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/expenses/preview'),
        body: jsonEncode({
          'amount': amount,
          'gst_rate': gstRate,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchCreditNoteDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchDebitNoteDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> finalizeCreditNote(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes/$id/finalize'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to finalize credit note';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> finalizeDebitNote(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes/$id/finalize'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to finalize debit note';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // PDF payloads
  Future<Map<String, dynamic>?> fetchInvoicePdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/$id/pdf-payload'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchProformaInvoicePdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/proforma-invoices/$id/pdf-payload'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchBillPdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/bills/$id/pdf-payload'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchPurchaseOrderPdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/purchase-orders/$id/pdf-payload'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchSalesOrderPdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales-orders/$id/pdf-payload'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  // Excel exports
  Future<Uint8List?> exportGstr1() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/gst/gstr1/export'));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> exportGstr2() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/gst/gstr2/export'));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> exportGstr3b() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/gst/gstr3b/export'));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  // Tax Templates & Payment Terms
  List<dynamic> _taxTemplates = [];

  Future<List<dynamic>> fetchTaxTemplates() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/tax-templates'));
      if (response.statusCode == 200) {
        _taxTemplates = jsonDecode(response.body);
        notifyListeners();
        return _taxTemplates;
      }
    } catch (_) {}
    return _taxTemplates;
  }

  List<dynamic> _paymentTerms = [];

  Future<List<dynamic>> fetchPaymentTerms() async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/payment-terms'));
      if (response.statusCode == 200) {
        _paymentTerms = jsonDecode(response.body);
        notifyListeners();
        return _paymentTerms;
      }
    } catch (_) {}
    return _paymentTerms;
  }

  Future<bool> _cancel(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse(url));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Cancel failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> _delete(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(Uri.parse(url));
      if (response.statusCode == 204) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Delete failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> _postAction(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse(url));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Action failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
}
