/// Invoice validation service — business rules for invoice integrity.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/invoice_line.dart';
import '../models/invoice_status.dart';

class InvoiceValidationService {
  const InvoiceValidationService();

  /// Result of a validation check.
  (bool valid, String? error) validateForSave({
    required String? contactId,
    required List<InvoiceLine> lines,
    required String posStateCode,
    String? issueDate,
    String? dueDate,
  }) {
    if (contactId == null || contactId.isEmpty) {
      return (false, 'Customer is required');
    }
    if (posStateCode.isEmpty || posStateCode.length != 2) {
      return (false, 'Place of Supply is required');
    }
    if (issueDate != null || dueDate != null) {
      final issue = DateTime.tryParse(issueDate ?? '');
      final due = DateTime.tryParse(dueDate ?? '');
      if (issue == null || due == null) {
        return (false, 'Invoice and due dates are required');
      }
      if (due.isBefore(issue)) {
        return (false, 'Due date cannot be before invoice date');
      }
    }
    if (lines.isEmpty) {
      return (false, 'At least one line item is required');
    }
    for (final line in lines) {
      final lineCheck = validateLine(line);
      if (!lineCheck.$1) return lineCheck;
    }
    return (true, null);
  }

  (bool valid, String? error) validateLine(InvoiceLine line) {
    if (line.productId.isEmpty) {
      return (false, 'Product is required on each line');
    }
    if (line.quantity <= 0) {
      return (false, 'Quantity must be greater than 0');
    }
    if (line.rate < 0) {
      return (false, 'Rate cannot be negative');
    }
    if (line.discount < 0 || line.discount > line.quantity * line.rate) {
      return (false, 'Line discount cannot exceed the line amount');
    }
    if (line.hsnSac.isEmpty || line.hsnSac.length < 4) {
      return (false, 'HSN/SAC code is required (min 4 digits)');
    }
    return (true, null);
  }

  (bool valid, String? error) validateStatusTransition(
    InvoiceStatus from,
    InvoiceStatus to,
  ) {
    if (from == InvoiceStatus.draft && to == InvoiceStatus.posted) {
      return (true, null);
    }
    if (from.isFinalized && to == InvoiceStatus.cancelled) {
      return (true, null);
    }
    return (false, 'Cannot transition from ${from.value} to ${to.value}');
  }
}

/// Provider for invoice validation service.
final invoiceValidationServiceProvider = Provider<InvoiceValidationService>((ref) {
  return const InvoiceValidationService();
});
