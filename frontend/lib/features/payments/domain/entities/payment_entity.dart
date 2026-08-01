/// Domain entity for a payment (receipt or disbursement).
library;

import 'package:flutter/foundation.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../core/utils/money.dart';

@immutable
class PaymentEntity {
  const PaymentEntity({
    required this.localId,
    required this.companyId,
    required this.paymentType,
    required this.paymentDate,
    required this.contactId,
    required this.contactName,
    required this.paymentMode,
    required this.accountId,
    required this.amountPaise,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
    this.remoteId,
    this.referenceNumber,
    this.description,
    this.syncError,
    this.lastSyncedAt,
    this.localRevision = 0,
  });

  final String localId;
  final String? remoteId;
  final String companyId;
  final String paymentType;
  final String paymentDate;
  final String? referenceNumber;
  final String contactId;
  final String contactName;
  final String paymentMode;
  final String accountId;
  final int amountPaise;
  final String? description;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final int localRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  bool get isDraft => lifecycleStatus == 'draft';
  bool get isPosted => lifecycleStatus == 'posted';
  bool get isReceipt => paymentType == 'RECEIPT';
  bool get isPayment => paymentType == 'PAYMENT';
  Money get amount => Money.fromPaise(amountPaise);
}

@immutable
class PaymentAllocationEntity {
  const PaymentAllocationEntity({
    required this.localId,
    required this.paymentLocalId,
    required this.invoiceLocalId,
    required this.allocatedPaise,
  });

  final String localId;
  final String paymentLocalId;
  final String invoiceLocalId;
  final int allocatedPaise;
}
