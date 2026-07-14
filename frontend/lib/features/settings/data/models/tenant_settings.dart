/// Tenant-wide operational and presentation settings returned by `/settings`.
library;

import 'package:flutter/foundation.dart';

@immutable
class TenantSettings {
  const TenantSettings({
    required this.id,
    required this.tenantId,
    this.logoUrl,
    this.currency = 'INR',
    this.gstEnabled = false,
    this.eInvoicingEnabled = false,
    this.eInvoiceUsername,
    this.eWayBillUsername,
    this.upiId,
    this.originStateCode,
    this.displaySettings = const {},
    this.extraSettings = const {},
  });

  factory TenantSettings.fromJson(Map<String, dynamic> json) => TenantSettings(
    id: (json['id'] ?? '').toString(),
    tenantId: (json['tenant_id'] ?? '').toString(),
    logoUrl: json['logo_url'] as String?,
    currency: json['currency'] as String? ?? 'INR',
    gstEnabled: json['gst_enabled'] as bool? ?? false,
    eInvoicingEnabled: json['e_invoicing_enabled'] as bool? ?? false,
    eInvoiceUsername: json['e_invoice_username'] as String?,
    eWayBillUsername: json['e_way_bill_username'] as String?,
    upiId: json['upi_id'] as String?,
    originStateCode: json['origin_state_code'] as String?,
    displaySettings: _map(json['display_settings']),
    extraSettings: _map(json['extra_settings']),
  );

  final String id;
  final String tenantId;
  final String? logoUrl;
  final String currency;
  final bool gstEnabled;
  final bool eInvoicingEnabled;
  final String? eInvoiceUsername;
  final String? eWayBillUsername;
  final String? upiId;
  final String? originStateCode;
  final Map<String, dynamic> displaySettings;
  final Map<String, dynamic> extraSettings;

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}
