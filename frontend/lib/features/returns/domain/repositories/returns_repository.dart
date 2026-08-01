library;

import '../entities/returns_entities.dart';
import '../commands/returns_commands.dart';

abstract interface class ReturnsRepository {
  /// Post a sales return.  Inside one transaction: create return + lines,
  /// increase inventory, reverse COGS (DEBIT inventory, CREDIT COGS),
  /// create receivable/tax reversal journal, create outbox.
  Future<SalesReturnEntity> postSalesReturn(PostSalesReturnCommand cmd);

  /// Post a purchase return.  Inside one transaction: create return + lines,
  /// decrease inventory, reverse GRIR/AP journal, create outbox.
  Future<PurchaseReturnEntity> postPurchaseReturn(
    PostPurchaseReturnCommand cmd,
  );

  Stream<List<SalesReturnEntity>> watchSalesReturns({String? companyId});
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturns({String? companyId});

  Future<SalesReturnEntity?> getSalesReturn(String localId);
  Future<PurchaseReturnEntity?> getPurchaseReturn(String localId);
}
