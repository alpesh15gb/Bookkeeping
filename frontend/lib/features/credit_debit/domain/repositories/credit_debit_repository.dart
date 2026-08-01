library;

import '../entities/credit_debit_entities.dart';
import '../commands/credit_debit_commands.dart';

abstract interface class CreditDebitRepository {
  /// Post a credit note.  Inside one transaction: consume number allocation,
  /// freeze credit note, create receivable/tax reversal journal, create outbox.
  Future<CreditNoteEntity> postCreditNote(PostCreditNoteCommand cmd);
  Future<DebitNoteEntity> postDebitNote(PostDebitNoteCommand cmd);
  Stream<List<CreditNoteEntity>> watchCreditNotes({String? companyId});
  Stream<List<DebitNoteEntity>> watchDebitNotes({String? companyId});
}
