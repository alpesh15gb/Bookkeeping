import 'package:flutter_client/models/contact.dart';

class RecurringInvoiceItemModel {
  final String? id;
  final String productId;
  final String? description;
  final double quantity;
  final double rate;
  final double discount;
  final String hsnSac;
  final double gstRate;

  RecurringInvoiceItemModel({
    this.id,
    required this.productId,
    this.description,
    required this.quantity,
    required this.rate,
    this.discount = 0.0,
    required this.hsnSac,
    required this.gstRate,
  });

  factory RecurringInvoiceItemModel.fromJson(Map<String, dynamic> json) {
    return RecurringInvoiceItemModel(
      id: json['id'],
      productId: json['product_id'] ?? '',
      description: json['description'],
      quantity: double.tryParse((json['quantity'] ?? 0.0).toString()) ?? 0.0,
      rate: double.tryParse((json['rate'] ?? 0.0).toString()) ?? 0.0,
      discount: double.tryParse((json['discount'] ?? 0.0).toString()) ?? 0.0,
      hsnSac: json['hsn_sac'] ?? '',
      gstRate: double.tryParse((json['gst_rate'] ?? 0.0).toString()) ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'product_id': productId,
      'description': description,
      'quantity': quantity,
      'rate': rate,
      'discount': discount,
      'hsn_sac': hsnSac,
      'gst_rate': gstRate,
    };
  }
}

class RecurringInvoiceModel {
  final String id;
  final String contactId;
  final String? contactName;
  final String templateName;
  final bool isActive;
  final String frequency;
  final int intervalCount;
  final String nextDate;
  final String endMode;
  final String? endDate;
  final int? maxOccurrences;
  final int occurrencesCreated;
  final String? lastGenerated;
  final String currency;
  final double exchangeRate;
  final String posStateCode;
  final String? notes;
  final String? termsAndConditions;
  final List<RecurringInvoiceItemModel> items;
  final ContactModel? contact;
  final String createdAt;

  RecurringInvoiceModel({
    required this.id,
    required this.contactId,
    this.contactName,
    required this.templateName,
    this.isActive = true,
    this.frequency = 'MONTHLY',
    this.intervalCount = 1,
    required this.nextDate,
    this.endMode = 'NEVER',
    this.endDate,
    this.maxOccurrences,
    this.occurrencesCreated = 0,
    this.lastGenerated,
    this.currency = 'INR',
    this.exchangeRate = 1.0,
    required this.posStateCode,
    this.notes,
    this.termsAndConditions,
    this.items = const [],
    this.contact,
    required this.createdAt,
  });

  factory RecurringInvoiceModel.fromJson(Map<String, dynamic> json) {
    var rawItems = (json['items'] is List ? json['items'] as List : []);
    List<RecurringInvoiceItemModel> itemsList = rawItems
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .map((x) => RecurringInvoiceItemModel.fromJson(x))
        .toList();

    return RecurringInvoiceModel(
      id: json['id'] ?? '',
      contactId: json['contact_id'] ?? '',
      contactName: json['contact_name'],
      templateName: json['template_name'] ?? '',
      isActive: json['is_active'] ?? true,
      frequency: json['frequency'] ?? 'MONTHLY',
      intervalCount: json['interval_count'] ?? 1,
      nextDate: json['next_date'] ?? '',
      endMode: json['end_mode'] ?? 'NEVER',
      endDate: json['end_date'],
      maxOccurrences: json['max_occurrences'],
      occurrencesCreated: json['occurrences_created'] ?? 0,
      lastGenerated: json['last_generated'],
      currency: json['currency'] ?? 'INR',
      exchangeRate: double.tryParse((json['exchange_rate'] ?? 1.0).toString()) ?? 1.0,
      posStateCode: json['pos_state_code'] ?? '27',
      notes: json['notes'],
      termsAndConditions: json['terms_and_conditions'],
      items: itemsList,
      contact: json['contact'] != null ? ContactModel.fromJson(json['contact']) : null,
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contact_id': contactId,
      'template_name': templateName,
      'frequency': frequency,
      'interval_count': intervalCount,
      'next_date': nextDate,
      'end_mode': endMode,
      'end_date': endDate,
      'max_occurrences': maxOccurrences,
      'currency': currency,
      'exchange_rate': exchangeRate,
      'pos_state_code': posStateCode,
      'notes': notes,
      'terms_and_conditions': termsAndConditions,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }

  String get frequencyLabel {
    switch (frequency) {
      case 'WEEKLY':
        return intervalCount > 1 ? 'Every $intervalCount weeks' : 'Weekly';
      case 'MONTHLY':
        return intervalCount > 1 ? 'Every $intervalCount months' : 'Monthly';
      case 'QUARTERLY':
        return intervalCount > 1 ? 'Every ${intervalCount * 3} months' : 'Quarterly';
      case 'YEARLY':
        return intervalCount > 1 ? 'Every $intervalCount years' : 'Yearly';
      default:
        return frequency;
    }
  }

  String get endModeLabel {
    switch (endMode) {
      case 'NEVER':
        return 'Never ends';
      case 'ON_DATE':
        return 'Ends on $endDate';
      case 'AFTER_N':
        return 'Ends after $maxOccurrences occurrences';
      default:
        return endMode;
    }
  }
}
