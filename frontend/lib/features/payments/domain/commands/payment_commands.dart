/// Commands for payment operations.
library;

import 'package:flutter/foundation.dart';

@immutable
class SavePaymentDraftCommand {
  const SavePaymentDraftCommand({
    required this.companyId,
    required this.paymentType,
    required this.paymentDate,
    required this.contactId,
    required this.contactName,
    required this.paymentMode,
    required this.accountId,
    required this.amountPaise,
    this.referenceNumber,
    this.description,
  });

  final String companyId;
  final String paymentType;
  final String paymentDate;
  final String contactId;
  final String contactName;
  final String paymentMode;
  final String accountId;
  final int amountPaise;
  final String? referenceNumber;
  final String? description;
}

@immutable
class PostPaymentCommand {
  const PostPaymentCommand({required this.localId, required this.companyId});

  final String localId;
  final String companyId;
}
