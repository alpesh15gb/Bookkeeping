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
    final extra = json['extra_settings'] is Map
        ? Map<String, dynamic>.from(json['extra_settings'] as Map)
        : const <String, dynamic>{};
    return GstConfig(
      taxMode: (json['tax_mode'] as String?) ?? TaxMode.nonGst,
      stateCode:
          json['origin_state_code'] as String? ?? json['state_code'] as String?,
      registrationType:
          extra['gst_registration_type'] as String? ??
          json['registration_type'] as String?,
      filingFrequency:
          extra['gst_filing_frequency'] as String? ??
          json['filing_frequency'] as String?,
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
      other is GstConfig &&
          runtimeType == other.runtimeType &&
          taxMode == other.taxMode &&
          stateCode == other.stateCode &&
          registrationType == other.registrationType &&
          filingFrequency == other.filingFrequency &&
          gstin == other.gstin;

  @override
  int get hashCode => Object.hash(taxMode, stateCode, registrationType, filingFrequency, gstin);
}

/// Known GST tax modes.
class TaxMode {
  TaxMode._();
  static const String regular = 'GST_REGULAR';
  static const String composition = 'GST_COMPOSITION';
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
    '25': 'Daman & Diu',
    '26': 'Dadra & Nagar Haveli and Daman & Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh (Old)',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman & Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
    '99': 'Centre Jurisdiction',
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
