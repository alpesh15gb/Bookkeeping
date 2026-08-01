/// Domain entity for an invoice in the offline-first layer.
library;

import 'package:flutter/foundation.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/core/utils/money.dart';

@immutable
class InvoiceEntity {
  const InvoiceEntity({
    required this.localId,
    required this.companyId,
    required this.invoiceDate,
    required this.customerId,
    required this.customerName,
    required this.totalPaise,
    required this.lines,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
    this.remoteId,
    this.number,
    this.displayNumber,
    this.allocationId,
    this.customerGstin,
    this.customerStateCode,
    this.dueDate,
    this.currency = 'INR',
    this.paymentTerms,
    this.referenceNumber,
    this.totalBeforeTaxPaise = 0,
    this.taxPaise = 0,
    this.discountPaise = 0,
    this.shippingPaise = 0,
    this.syncError,
    this.lastSyncedAt,
    this.localRevision = 0,
    this.remoteRevision,
  });

  final String localId;
  final String? remoteId;
  final String companyId;
  final int? number;
  final String? displayNumber;
  final String? allocationId;
  final String invoiceDate;
  final String? dueDate;
  final String customerId;
  final String customerName;
  final String? customerGstin;
  final String? customerStateCode;
  final String currency;
  final String? paymentTerms;
  final String? referenceNumber;
  final int totalBeforeTaxPaise;
  final int taxPaise;
  final int discountPaise;
  final int shippingPaise;
  final int totalPaise;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final int localRevision;
  final int? remoteRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSyncedAt;
  final String? syncError;
  final List<InvoiceLineEntity> lines;

  bool get isDraft => lifecycleStatus == 'draft';
  bool get isIssued => lifecycleStatus == 'issued';
  bool get isSynced => syncStatus == SyncStatus.synced;
  bool get hasSyncIssue => syncStatus.requiresAttention;
  Money get total => Money.fromPaise(totalPaise);
}

@immutable
class InvoiceLineEntity {
  const InvoiceLineEntity({
    required this.localId,
    required this.invoiceLocalId,
    required this.productName,
    required this.unitPricePaise,
    required this.quantity,
    required this.amountPaise,
    required this.netPaise,
    required this.sortOrder,
    this.productId,
    this.description,
    this.hsnSac,
    this.discountPaise = 0,
    this.taxRateBasisPoints = 0,
    this.taxPaise = 0,
  });

  final String localId;
  final String invoiceLocalId;
  final String? productId;
  final String productName;
  final String? description;
  final String? hsnSac;
  final int unitPricePaise;
  final String quantity;
  final int amountPaise;
  final int discountPaise;
  final int taxRateBasisPoints;
  final int taxPaise;
  final int netPaise;
  final int sortOrder;
}

@immutable
class InvoiceTaxLineEntity {
  const InvoiceTaxLineEntity({
    required this.localId,
    required this.invoiceLocalId,
    required this.lineLocalId,
    required this.taxType,
    required this.taxRate,
    required this.taxableAmountPaise,
    required this.taxAmountPaise,
  });
  final String localId;
  final String invoiceLocalId;
  final String lineLocalId;
  final String taxType;
  final String taxRate;
  final int taxableAmountPaise;
  final int taxAmountPaise;
}

/// Describes a pre-allocated number range.
class NumberAllocationEntity {
  const NumberAllocationEntity({
    required this.localId,
    required this.allocationId,
    required this.companyId,
    required this.deviceId,
    required this.financialYearId,
    required this.series,
    required this.documentType,
    required this.fromNum,
    required this.toNum,
    required this.used,
    this.prefix = '',
    this.suffix,
    this.paddingDigits = 4,
  });

  final String localId;
  final String allocationId;
  final String companyId;
  final String deviceId;
  final String financialYearId;
  final String series;
  final String documentType;
  final int fromNum;
  final int toNum;
  final int used;
  final String prefix;
  final String? suffix;
  final int paddingDigits;

  int get remaining => toNum - fromNum + 1 - used;
  bool get isExhausted => remaining <= 0;
  int get nextNumber => fromNum + used;
  String get nextDisplayNumber =>
      '$prefix${nextNumber.toString().padLeft(paddingDigits, '0')}${suffix ?? ''}';
}
