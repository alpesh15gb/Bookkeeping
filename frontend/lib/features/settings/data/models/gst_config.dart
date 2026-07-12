/// GST configuration model for the company.
library;

import 'package:flutter/foundation.dart';

/// GST-related settings: tax mode, state, registration type, and filing.
@immutable
class GstConfig {
  const GstConfig({
    required this.taxMode,
    this.stateCode,
    this.registrationType,
    this.filingFrequency,
    this.gstin,
  });

  factory GstConfig.fromJson(Map<String, dynamic> json) {
    return GstConfig(
      taxMode: (json['tax_mode'] as String?) ?? 'NON_GST',
      stateCode: json['state_code'] as String?,
      registrationType: json['registration_type'] as String?,
      filingFrequency: json['filing_frequency'] as String?,
      gstin: json['gstin'] as String?,
    );
  }

  final String taxMode;
  final String? stateCode;
  final String? registrationType;
  final String? filingFrequency;
  final String? gstin;

  Map<String, dynamic> toJson() => {
    'tax_mode': taxMode,
    if (stateCode != null) 'state_code': stateCode,
    if (registrationType != null) 'registration_type': registrationType,
    if (filingFrequency != null) 'filing_frequency': filingFrequency,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GstConfig && runtimeType == other.runtimeType;

  @override
  int get hashCode => Object.hash(taxMode, stateCode, registrationType);
}

/// Known GST tax modes.
class TaxMode {
  TaxMode._();
  static const String regular = 'REGULAR';
  static const String composition = 'COMPOSITION';
  static const String nonGst = 'NON_GST';

  static Map<String, String> get labels => {
    regular: 'Regular',
    composition: 'Composition',
    nonGst: 'Non-GST',
  };
}

/// Indian state codes for GST.
class IndianStates {
  IndianStates._();

  static const Map<String, String> codes = {
    '01': 'Jammu & Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '25': 'Daman & Diu and Dadra & Nagar Haveli',
    '26': 'Maharashtra',
    '27': 'Karnataka',
    '28': 'Andhra Pradesh',
    '29': 'Kerala',
    '30': 'Tamil Nadu',
    '31': 'Puducherry',
    '32': 'Lakshadweep',
    '33': 'Andaman & Nicobar Islands',
    '34': 'Telangana',
    '35': 'Andhra Pradesh (New)',
    '36': 'Ladakh',
    '37': 'Goa',
    '38': 'Goa',
    '97': 'Other Territory',
    '99': 'E-Commerce Operator',
  };
}

/// Registration types for GST.
class RegistrationType {
  RegistrationType._();
  static const String regular = 'regular';
  static const String casual = 'casual';
  static const String nonResident = 'non_resident';
  static const String unregistered = 'unregistered';

  static Map<String, String> get labels => {
    regular: 'Regular',
    casual: 'Casual Taxable Person',
    nonResident: 'Non-Resident Taxable Person',
    unregistered: 'Unregistered',
  };
}

/// Filing frequency options.
class FilingFrequency {
  FilingFrequency._();
  static const String monthly = 'monthly';
  static const String quarterly = 'quarterly';

  static Map<String, String> get labels => {
    monthly: 'Monthly (GSTR-3B & GSTR-1)',
    quarterly: 'Quarterly (QRMP Scheme)',
  };
}
