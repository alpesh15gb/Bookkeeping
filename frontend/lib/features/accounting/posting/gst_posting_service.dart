/// GST posting service — stub for GST liability tracking.
///
/// Each taxable transaction should post GST output/input tax through this
/// service so that GSTR-1, GSTR-3B, and other compliance reports are
/// consistent with the underlying ledgers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ledger_posting_service.dart';

/// GST posting service — handles tax component allocation.
class GSTPostingService {
  GSTPostingService();

  /// Post GST components from an invoice to appropriate tax accounts.
  Future<List<PostingLine>> postOutputGst({
    required String tenantId,
    required String documentId,
    required String documentNumber,
    required String date,
    required String cgstAccountId,
    required String sgstAccountId,
    required String igstAccountId,
    String? cessAccountId,
    required double cgstAmount,
    required double sgstAmount,
    required double igstAmount,
    double cessAmount = 0,
  }) async {
    final lines = <PostingLine>[];
    if (cgstAmount > 0) {
      lines.add(
        PostingLine(
          accountId: cgstAccountId,
          debit: 0,
          credit: cgstAmount,
          description: 'CGST on $documentNumber',
        ),
      );
    }
    if (sgstAmount > 0) {
      lines.add(
        PostingLine(
          accountId: sgstAccountId,
          debit: 0,
          credit: sgstAmount,
          description: 'SGST on $documentNumber',
        ),
      );
    }
    if (igstAmount > 0) {
      lines.add(
        PostingLine(
          accountId: igstAccountId,
          debit: 0,
          credit: igstAmount,
          description: 'IGST on $documentNumber',
        ),
      );
    }
    if (cessAmount > 0 && cessAccountId != null) {
      lines.add(
        PostingLine(
          accountId: cessAccountId,
          debit: 0,
          credit: cessAmount,
          description: 'CESS on $documentNumber',
        ),
      );
    }
    return lines;
  }
}

final gstPostingServiceProvider = Provider<GSTPostingService>((ref) {
  return GSTPostingService();
});
