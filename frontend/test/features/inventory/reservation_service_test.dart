// Tests for ReservationService — state machine, availability, totalReserved.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/inventory/reservation/services/reservation_service.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';

void main() {
  const svc = ReservationService();

  group('ReservationStatus', () {
    test('isActive true for reserved and committed', () {
      expect(ReservationStatus.reserved.isActive, true);
      expect(ReservationStatus.committed.isActive, true);
      expect(ReservationStatus.available.isActive, false);
      expect(ReservationStatus.released.isActive, false);
    });
    test('canReserve only for available', () {
      expect(ReservationStatus.available.canReserve, true);
      expect(ReservationStatus.reserved.canReserve, false);
    });
    test('canCommit only for reserved', () {
      expect(ReservationStatus.reserved.canCommit, true);
      expect(ReservationStatus.committed.canCommit, false);
    });
    test('canRelease for reserved or committed', () {
      expect(ReservationStatus.reserved.canRelease, true);
      expect(ReservationStatus.committed.canRelease, true);
      expect(ReservationStatus.released.canRelease, false);
    });
  });

  group('validateTransition', () {
    test('Available → Reserved allowed', () {
      expect(
        svc.validateTransition(
          current: ReservationStatus.available,
          target: ReservationStatus.reserved,
        ),
        isNull,
      );
    });
    test('Available → Committed rejected', () {
      expect(
        svc.validateTransition(
          current: ReservationStatus.available,
          target: ReservationStatus.committed,
        ),
        isNotNull,
      );
    });
    test('Reserved → Committed allowed', () {
      expect(
        svc.validateTransition(
          current: ReservationStatus.reserved,
          target: ReservationStatus.committed,
        ),
        isNull,
      );
    });
    test('Reserved → Released allowed', () {
      expect(
        svc.validateTransition(
          current: ReservationStatus.reserved,
          target: ReservationStatus.released,
        ),
        isNull,
      );
    });
    test('Committed → Released allowed', () {
      expect(
        svc.validateTransition(
          current: ReservationStatus.committed,
          target: ReservationStatus.released,
        ),
        isNull,
      );
    });
    test('Released → any rejected (terminal)', () {
      expect(
        svc.validateTransition(
          current: ReservationStatus.released,
          target: ReservationStatus.reserved,
        ),
        isNotNull,
      );
    });
    test('Available → Released rejected', () {
      expect(
        svc.validateTransition(
          current: ReservationStatus.available,
          target: ReservationStatus.released,
        ),
        isNotNull,
      );
    });
  });

  group('validateAvailability', () {
    test('sufficient stock with block policy', () {
      expect(
        svc.validateAvailability(
          requestedQuantity: 5,
          availableStock: 100,
          existingReservations: 10,
          policy: NegativeStockPolicy.block,
        ),
        isNull,
      );
    });
    test('insufficient stock blocked', () {
      final r = svc.validateAvailability(
        requestedQuantity: 50,
        availableStock: 100,
        existingReservations: 60,
        policy: NegativeStockPolicy.block,
      );
      expect(r, isNotNull);
      expect(r, contains('Insufficient'));
    });
    test('insufficient stock with warn policy passes', () {
      expect(
        svc.validateAvailability(
          requestedQuantity: 50,
          availableStock: 100,
          existingReservations: 60,
          policy: NegativeStockPolicy.warn,
        ),
        isNull,
      );
    });
    test('insufficient stock with allow policy passes', () {
      expect(
        svc.validateAvailability(
          requestedQuantity: 50,
          availableStock: 100,
          existingReservations: 60,
          policy: NegativeStockPolicy.allow,
        ),
        isNull,
      );
    });
    test('zero quantity rejected', () {
      expect(
        svc.validateAvailability(
          requestedQuantity: 0,
          availableStock: 100,
          existingReservations: 0,
        ),
        isNotNull,
      );
    });
    test('negative quantity rejected', () {
      expect(
        svc.validateAvailability(
          requestedQuantity: -1,
          availableStock: 100,
          existingReservations: 0,
        ),
        isNotNull,
      );
    });
  });

  group('totalReserved', () {
    test('sums only reserved status', () {
      final reservations = [
        Reservation(
          id: 'r1',
          productId: 'p1',
          productName: 'P1',
          quantity: 10,
          status: ReservationStatus.reserved,
        ),
        Reservation(
          id: 'r2',
          productId: 'p1',
          productName: 'P1',
          quantity: 5,
          status: ReservationStatus.reserved,
        ),
        Reservation(
          id: 'r3',
          productId: 'p1',
          productName: 'P1',
          quantity: 3,
          status: ReservationStatus.committed,
        ),
      ];
      expect(svc.totalReserved(reservations, 'p1'), 15.0);
    });
    test('zero for no reservations', () {
      expect(svc.totalReserved([], 'p1'), 0);
    });
    test('zero for other product', () {
      final reservations = [
        Reservation(
          id: 'r1',
          productId: 'p2',
          productName: 'P2',
          quantity: 10,
          status: ReservationStatus.reserved,
        ),
      ];
      expect(svc.totalReserved(reservations, 'p1'), 0);
    });
  });

  group('Reservation.fromJson', () {
    test('parses full JSON', () {
      final r = Reservation.fromJson({
        'id': 'r1',
        'product_id': 'p1',
        'product_name': 'Widget',
        'quantity': 25,
        'status': 'reserved',
        'reference_type': 'SALES_ORDER',
        'reference_id': 'so-1',
        'warehouse_id': 'wh-1',
      });
      expect(r.id, 'r1');
      expect(r.productId, 'p1');
      expect(r.quantity, 25.0);
      expect(r.status, ReservationStatus.reserved);
    });
    test('defaults on minimal JSON', () {
      final r = Reservation.fromJson({'id': 'r1'});
      expect(r.status, ReservationStatus.available);
      expect(r.quantity, 0);
    });
  });
}
