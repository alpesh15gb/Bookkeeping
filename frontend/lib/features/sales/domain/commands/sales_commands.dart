/// Commands for sales fulfillment.
library;

import 'package:flutter/foundation.dart';

@immutable
class SaveSalesOrderDraftCommand {
  const SaveSalesOrderDraftCommand({
    required this.companyId,
    required this.orderDate,
    required this.customerId,
    required this.customerName,
    this.referenceNumber,
    this.description,
    this.totalPaise = 0,
    this.lines = const [],
  });
  final String companyId;
  final String orderDate;
  final String customerId;
  final String customerName;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final List<SalesOrderLineCommand> lines;
}

@immutable
class SalesOrderLineCommand {
  const SalesOrderLineCommand({
    required this.productName,
    required this.unit,
    required this.unitPricePaise,
    required this.quantityOrdered,
    required this.totalPaise,
    required this.sortOrder,
    this.description,
  });
  final String productName;
  final String? description;
  final String unit;
  final int unitPricePaise;
  final String quantityOrdered;
  final int totalPaise;
  final int sortOrder;
}

@immutable
class DeliverGoodsCommand {
  const DeliverGoodsCommand({
    required this.companyId,
    required this.salesOrderLocalId,
    required this.deliveryDate,
    required this.customerId,
    required this.customerName,
    this.referenceNumber,
    this.description,
    required this.lines,
  });
  final String companyId;
  final String salesOrderLocalId;
  final String deliveryDate;
  final String customerId;
  final String customerName;
  final String? referenceNumber;
  final String? description;
  final List<SalesDeliveryLineCommand> lines;
}

@immutable
class SalesDeliveryLineCommand {
  const SalesDeliveryLineCommand({
    required this.salesOrderLineLocalId,
    required this.productName,
    required this.unit,
    required this.quantityDelivered,
    required this.unitPricePaise,
    required this.sortOrder,
  });
  final String salesOrderLineLocalId;
  final String productName;
  final String unit;
  final String quantityDelivered;
  final int unitPricePaise;
  final int sortOrder;
}

@immutable
class CreateInvoiceFromDeliveryCommand {
  const CreateInvoiceFromDeliveryCommand({
    required this.companyId,
    required this.deliveryLocalId,
    required this.invoiceDate,
    required this.customerId,
    required this.customerName,
    required this.deviceId,
    required this.financialYearId,
    required this.series,
    this.referenceNumber,
    this.taxPaise = 0,
    this.totalPaise = 0,
  });

  final String companyId;
  final String deliveryLocalId;
  final String invoiceDate;
  final String customerId;
  final String customerName;
  final String deviceId;
  final String financialYearId;
  final String series;
  final String? referenceNumber;
  final int taxPaise;
  final int totalPaise;
}
