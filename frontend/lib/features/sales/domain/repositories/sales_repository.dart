/// Repository interface for sales fulfillment.
library;

import '../entities/sales_entities.dart';
import '../commands/sales_commands.dart';

abstract interface class SalesRepository {
  Stream<List<SalesOrderEntity>> watchSalesOrders({String? companyId});
  Future<SalesOrderEntity?> getSalesOrder(String localId);
  Future<SalesOrderEntity> saveSalesOrderDraft(SaveSalesOrderDraftCommand cmd);

  /// Deliver goods.  Inside one transaction: create delivery, reduce stock,
  /// write ISSUE movements, create COGS journal, update order status, outbox.
  Future<SalesDeliveryEntity> deliverGoods(DeliverGoodsCommand cmd);

  /// Create customer invoice from delivery.  Inside one transaction:
  /// consume number allocation, freeze invoice, create receivable/revenue
  /// journal, mark delivery as invoiced, create outbox.
  Future<SalesOrderEntity> createInvoiceFromDelivery(
    CreateInvoiceFromDeliveryCommand cmd,
  );

  Stream<List<SalesDeliveryEntity>> watchDeliveries({String? companyId});
  Future<SalesDeliveryEntity?> getDelivery(String localId);
}
