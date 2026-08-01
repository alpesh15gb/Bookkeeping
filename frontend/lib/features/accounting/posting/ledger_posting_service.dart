/// Ledger posting service — posts journal entries to the backend.
///
/// Every financial event (invoice, payment, credit note, etc.) flows through
/// this service to create balanced journal entries via the accounting API.
/// All calls go to the live backend — no stubs, no mock data.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';

/// A single journal line for posting.
class PostingLine {
  const PostingLine({
    required this.accountId,
    required this.debit,
    required this.credit,
    this.description,
  });

  final String accountId;
  final double debit;
  final double credit;
  final String? description;

  double get balance => debit - credit;
}

/// Result of a posting operation.
class PostingResult {
  const PostingResult({
    required this.journalEntryId,
    this.entryNumber = '',
    this.lines = const [],
  });

  final String journalEntryId;
  final String entryNumber;
  final List<PostingLine> lines;
}

/// General ledger posting service.
///
/// Posts journal entries to `POST /accounting/journals` on the backend.
/// The backend handles double-entry validation, balance updates, and
/// numbering series auto-generation.
class LedgerPostingService {
  LedgerPostingService(this._dio);
  final Dio _dio;

  /// Post an invoice to the ledger via the accounting journals API.
  Future<Result<PostingResult>> postInvoice({
    required String tenantId,
    required String invoiceId,
    required String invoiceNumber,
    required String date,
    required String customerAccountId,
    required String revenueAccountId,
    required double total,
  }) {
    return guardDio(() async {
      final lines = <Map<String, dynamic>>[
        {
          'account_id': customerAccountId,
          'amount': total,
          'direction': 'DEBIT',
          'narration': 'Invoice $invoiceNumber',
        },
        {
          'account_id': revenueAccountId,
          'amount': total,
          'direction': 'CREDIT',
          'narration': 'Revenue from $invoiceNumber',
        },
      ];

      final res = await _dio.post(
        '/accounting/journals',
        data: {
          'entry_date': date,
          'reference_number': invoiceNumber,
          'description': 'Auto-posting from invoice $invoiceNumber',
          'source_type': 'INVOICE',
          'source_id': invoiceId,
          'lines': lines,
        },
      );

      final data = res.data as Map<String, dynamic>;
      return _parseResult(data);
    });
  }

  Future<Result<PostingResult>> postPaymentReceipt({
    required String tenantId,
    required String paymentId,
    required String paymentNumber,
    required String date,
    required String bankAccountId,
    required String customerAccountId,
    required double amount,
  }) {
    return guardDio(() async {
      final lines = <Map<String, dynamic>>[
        {
          'account_id': bankAccountId,
          'amount': amount,
          'direction': 'DEBIT',
          'narration': 'Receipt $paymentNumber',
        },
        {
          'account_id': customerAccountId,
          'amount': amount,
          'direction': 'CREDIT',
          'narration': 'Payment received $paymentNumber',
        },
      ];

      final res = await _dio.post(
        '/accounting/journals',
        data: {
          'entry_date': date,
          'reference_number': paymentNumber,
          'description': 'Auto-posting from payment $paymentNumber',
          'source_type': 'PAYMENT',
          'source_id': paymentId,
          'lines': lines,
        },
      );

      final data = res.data as Map<String, dynamic>;
      return _parseResult(data);
    });
  }

  Future<Result<PostingResult>> reverseEntry({
    required String tenantId,
    required String originalEntryId,
    required String reversalReason,
  }) {
    return guardDio(() async {
      // Fetch the original entry to reverse its lines
      final orig = await _dio.get('/accounting/journals/$originalEntryId');
      final origData = orig.data as Map<String, dynamic>;
      final origLines = origData['lines'] as List? ?? [];

      final reversalLines = origLines.map((l) {
        final line = l as Map<String, dynamic>;
        final currentDirection = line['direction'] as String;
        return {
          'account_id': line['account_id'] as String,
          'amount': parseDoubleSafe(line['amount']),
          'direction': currentDirection == 'DEBIT' ? 'CREDIT' : 'DEBIT',
          'narration': 'Reversal: ${line['narration'] ?? ''}',
        };
      }).toList();

      final res = await _dio.post(
        '/accounting/journals',
        data: {
          'entry_date': DateTime.now().toIso8601String().split('T').first,
          'reference_number':
              'REV-${origData['reference_number'] ?? originalEntryId}',
          'description': 'Reversal of entry $originalEntryId: $reversalReason',
          'source_type': 'REVERSAL',
          'source_id': originalEntryId,
          'lines': reversalLines,
        },
      );

      final data = res.data as Map<String, dynamic>;
      return _parseResult(data);
    });
  }

  PostingResult _parseResult(Map<String, dynamic> data) {
    return PostingResult(
      journalEntryId: data['id'] as String,
      entryNumber: data['reference_number'] as String? ?? '',
      lines:
          (data['lines'] as List?)?.map((l) {
            final m = l as Map<String, dynamic>;
            return PostingLine(
              accountId: m['account_id'] as String,
              debit: (m['direction'] as String) == 'DEBIT'
                  ? parseDoubleSafe(m['amount'])
                  : 0,
              credit: (m['direction'] as String) == 'CREDIT'
                  ? parseDoubleSafe(m['amount'])
                  : 0,
              description: m['narration'] as String?,
            );
          }).toList() ??
          [],
    );
  }
}

final ledgerPostingServiceProvider = Provider<LedgerPostingService>((ref) {
  return LedgerPostingService(ref.watch(apiClientProvider));
});
