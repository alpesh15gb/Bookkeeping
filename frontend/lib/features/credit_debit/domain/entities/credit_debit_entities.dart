library;

import 'package:flutter/foundation.dart';
import '../../../../core/sync/sync_status.dart';

@immutable
class CreditNoteEntity {
  const CreditNoteEntity({
    required this.localId,
    required this.companyId,
    required this.creditNoteDate,
    required this.customerId,
    required this.customerName,
    required this.totalPaise,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    this.number,
    this.allocationId,
    this.sourceInvoiceLocalId,
    this.referenceNumber,
    this.description,
    this.syncError,
  });
  final String localId;
  final String companyId;
  final String creditNoteDate;
  final String customerId;
  final String customerName;
  final int? number;
  final String? allocationId;
  final String? sourceInvoiceLocalId;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  bool get isPosted => lifecycleStatus == 'posted';
}

@immutable
class DebitNoteEntity {
  const DebitNoteEntity({
    required this.localId,
    required this.companyId,
    required this.debitNoteDate,
    required this.supplierId,
    required this.supplierName,
    required this.totalPaise,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    this.number,
    this.allocationId,
    this.sourceInvoiceLocalId,
    this.referenceNumber,
    this.description,
    this.syncError,
  });
  final String localId;
  final String companyId;
  final String debitNoteDate;
  final String supplierId;
  final String supplierName;
  final int? number;
  final String? allocationId;
  final String? sourceInvoiceLocalId;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
}
