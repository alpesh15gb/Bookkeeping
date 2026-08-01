/// Repository interface for the purchasing workflow.
library;

import '../entities/purchasing_entities.dart';
import '../commands/purchasing_commands.dart';

abstract interface class PurchasingRepository {
  // ── Purchase orders ──────────────────────────────────────────────────────
  Stream<List<PurchaseOrderEntity>> watchPurchaseOrders({String? companyId});
  Future<PurchaseOrderEntity?> getPurchaseOrder(String localId);
  Future<PurchaseOrderEntity> savePurchaseOrderDraft(
    SavePurchaseOrderDraftCommand cmd,
  );

  // ── Goods receipt ────────────────────────────────────────────────────────
  Future<PurchaseReceiptEntity> receiveGoods(ReceiveGoodsCommand cmd);

  // ── Supplier invoices ────────────────────────────────────────────────────
  Future<PurchaseInvoiceEntity> postSupplierInvoice(
    PostSupplierInvoiceCommand cmd,
  );

  // ── Read ─────────────────────────────────────────────────────────────────
  Stream<List<PurchaseReceiptEntity>> watchReceipts({String? companyId});
  Future<PurchaseReceiptEntity?> getReceipt(String localId);
  Stream<List<PurchaseInvoiceEntity>> watchPurchaseInvoices({
    String? companyId,
  });
  Future<PurchaseInvoiceEntity?> getPurchaseInvoice(String localId);
}
