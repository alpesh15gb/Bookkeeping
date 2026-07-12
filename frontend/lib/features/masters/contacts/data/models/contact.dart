/// Contact model — matches the backend /masters/contacts API contract exactly.
/// Source: docs/REQUEST_RESPONSE_REFERENCE.md
library;

import 'package:flutter/foundation.dart';
import 'package:apexbooks/core/api/base_model.dart';

/// contact_type values from the backend.
enum ContactType {
  customer,
  vendor,
  both;

  String get apiValue => name.toUpperCase();
  static ContactType fromApi(String v) =>
      ContactType.values.firstWhere((e) => e.apiValue == v, orElse: () => both);

  String get displayLabel => switch (this) {
    ContactType.customer => 'Customer',
    ContactType.vendor => 'Vendor',
    ContactType.both => 'Both',
  };
}

/// registration_type values from the backend.
enum RegistrationType {
  regular,
  composition,
  consumer,
  unregistered,
  sez,
  overseas;

  String get apiValue => name.toUpperCase();
  static RegistrationType fromApi(String v) => RegistrationType.values
      .firstWhere((e) => e.apiValue == v, orElse: () => regular);
}

/// Nested address object used by billing_address and shipping_address.
class Address {
  final String? street;
  final String? city;
  final String? state;
  final String? stateCode;
  final String? pincode;
  final String? country;

  const Address({
    this.street,
    this.city,
    this.state,
    this.stateCode,
    this.pincode,
    this.country,
  });

  static Address? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return Address(
      street: json['street'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      stateCode: json['state_code'] as String?,
      pincode: json['pincode'] as String?,
      country: json['country'] as String?,
    );
  }

  Map<String, dynamic>? toJson() {
    if (street == null &&
        city == null &&
        state == null &&
        stateCode == null &&
        pincode == null &&
        country == null)
      return null;
    return {
      if (street != null) 'street': street,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (stateCode != null) 'state_code': stateCode,
      if (pincode != null) 'pincode': pincode,
      if (country != null) 'country': country,
    };
  }
}

/// Contact — matches ContactResponse from the backend.
@immutable
class Contact extends BaseModel {
  const Contact({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.contactType = ContactType.both,
    this.gstin,
    this.pan,
    this.registrationType = RegistrationType.regular,
    this.billingAddress,
    this.shippingAddress,
    this.stateCode,
    this.isActive = true,
    this.openingBalance = 0,
    this.creditBalance = 0,
    this.customFields,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final ContactType contactType;
  final String? gstin;
  final String? pan;
  final RegistrationType registrationType;
  final Address? billingAddress;
  final Address? shippingAddress;
  final String? stateCode;
  final bool isActive;
  final double openingBalance;
  final double creditBalance;
  final Map<String, dynamic>? customFields;
  final String? createdAt;
  final String? updatedAt;

  @override
  Contact fromJson(Map<String, dynamic> json) => Contact(
    id: (json['id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    contactType: json['contact_type'] != null
        ? ContactType.fromApi(json['contact_type'] as String)
        : ContactType.both,
    gstin: json['gstin'] as String?,
    pan: json['pan'] as String?,
    registrationType: json['registration_type'] != null
        ? RegistrationType.fromApi(json['registration_type'] as String)
        : RegistrationType.regular,
    billingAddress: Address.fromJson(
      (json['billing_address'] as Map?)?.cast<String, dynamic>(),
    ),
    shippingAddress: Address.fromJson(
      (json['shipping_address'] as Map?)?.cast<String, dynamic>(),
    ),
    stateCode: json['state_code'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    openingBalance: _parseDecimal(json['opening_balance']),
    creditBalance: _parseDecimal(json['credit_balance']),
    customFields: (json['custom_fields'] as Map?)?.cast<String, dynamic>(),
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    'contact_type': contactType.apiValue,
    if (gstin != null) 'gstin': gstin,
    if (pan != null) 'pan': pan,
    'registration_type': registrationType.apiValue,
    if (billingAddress != null) 'billing_address': billingAddress!.toJson(),
    if (shippingAddress != null) 'shipping_address': shippingAddress!.toJson(),
    if (stateCode != null) 'state_code': stateCode,
    'is_active': isActive,
    if (openingBalance != 0)
      'opening_balance': openingBalance.toStringAsFixed(2),
    if (customFields != null) 'custom_fields': customFields,
  };

  @override
  String toString() => name;

  static double _parseDecimal(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
