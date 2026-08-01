library;

import '../entities/banking_entities.dart';
import '../commands/banking_commands.dart';

abstract interface class BankingRepository {
  Future<BankStatementEntity> importStatement(ImportStatementCommand cmd);
  Future<BankMatchEntity> matchLine(MatchStatementLineCommand cmd);
  Future<ReconciliationEntity> finalizeReconciliation(
    FinalizeReconciliationCommand cmd,
  );
  Stream<List<BankStatementEntity>> watchStatements({String? companyId});
}
