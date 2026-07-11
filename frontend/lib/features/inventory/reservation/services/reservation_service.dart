/// Reservation state machine for inventory.
///
/// Sales Orders and Delivery Challans will use this to reserve stock before
/// finalizing an invoice. The lifecycle is:
///
///   Available
///       ↓
///   Reserved  ← stock is held for an order
///       ↓
///   Committed ← stock is deducted (invoice finalized)
///       ↓
///   Released  ← order cancelled, stock freed
library;

import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';

/// States of a stock reservation.
enum ReservationStatus {
  /// Stock is available for reservation.
  available,

  /// Stock has been reserved for a specific order.
  reserved,

  /// Stock has been committed/deducted (invoice finalized).
  committed,

  /// Reservation has been released (cancelled order).
  released;

  bool get isActive => this == reserved || this == committed;
  bool get isAvailable => this == available;
  bool get canReserve => this == available;
  bool get canCommit => this == reserved;
  bool get canRelease => this == reserved || this == committed;
  bool get canCancel => this == reserved;
}

/// A reservation entry for a specific product against a reference document.
class Reservation {
  const Reservation({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.status,
    this.referenceType,
    this.referenceId,
    this.warehouseId,
    this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final ReservationStatus status;
  final String? referenceType;
  final String? referenceId;
  final String? warehouseId;
  final String? createdAt;

  factory Reservation.fromJson(Map<String, dynamic> json) => Reservation(
    id: (json['id'] ?? '').toString(),
    productId: (json['product_id'] ?? '').toString(),
    productName: json['product_name'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
    status: _parseStatus(json['status'] as String? ?? ''),
    referenceType: json['reference_type'] as String?,
    referenceId: json['reference_id']?.toString(),
    warehouseId: json['warehouse_id']?.toString(),
    createdAt: json['created_at'] as String?,
  );

  static ReservationStatus _parseStatus(String s) =>
      ReservationStatus.values.firstWhere(
        (e) => e.name == s.toLowerCase(),
        orElse: () => ReservationStatus.available,
      );
}

/// Pure reservation engine — all business logic, no UI or API.
class ReservationService {
  const ReservationService();

  /// Check if a reservation transition is valid.
  /// Returns `null` if allowed, or an error message if rejected.
  String? validateTransition({
    required ReservationStatus current,
    required ReservationStatus target,
  }) {
    switch (current) {
      case ReservationStatus.available:
        if (target == ReservationStatus.reserved) return null;
        return 'Can only transition Available → Reserved';
      case ReservationStatus.reserved:
        if (target == ReservationStatus.committed) return null;
        if (target == ReservationStatus.released) return null;
        return 'Can only transition Reserved → Committed or Reserved → Released';
      case ReservationStatus.committed:
        if (target == ReservationStatus.released) return null;
        return 'Can only transition Committed → Released';
      case ReservationStatus.released:
        return 'Released is a terminal state. No further transitions allowed.';
    }
  }

  /// Check if enough stock is available for a reservation.
  /// `availableStock` is the current on-hand quantity.
  /// `existingReservations` is the sum of active reservations for this product.
  String? validateAvailability({
    required double requestedQuantity,
    required double availableStock,
    required double existingReservations,
    NegativeStockPolicy policy = NegativeStockPolicy.warn,
  }) {
    if (requestedQuantity <= 0) {
      return 'Requested quantity must be greater than zero';
    }
    final remaining = availableStock - existingReservations;
    if (remaining < requestedQuantity) {
      if (policy == NegativeStockPolicy.block) {
        return 'Insufficient stock: requested $requestedQuantity, available $remaining';
      }
      if (policy == NegativeStockPolicy.warn) {
        // Return null (allowed) but the caller can check remaining vs requested
        // to show a warning.
        return null;
      }
      // allow — no check
    }
    return null;
  }

  /// Get total reserved quantity from a list of reservations.
  double totalReserved(List<Reservation> reservations, String productId) {
    return reservations
        .where(
          (r) =>
              r.productId == productId &&
              r.status == ReservationStatus.reserved,
        )
        .fold<double>(0, (s, r) => s + r.quantity);
  }
}
