// Tests for Three-Way Matching — the strongest procurement control.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/purchases/matching/models/match_models.dart';
import 'package:apexbooks/features/purchases/matching/services/three_way_matching_service.dart';

void main() {
  const svc = ThreeWayMatchingService();

  group('perfect match', () {
    test('no discrepancies when all match', () {
      final result = svc.match(
        poTotal: 1180,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 10,
            billedQuantity: 10,
            billedRate: 100,
          ),
        ],
      );
      expect(result.isMatched, true);
      expect(result.discrepancies, isEmpty);
      expect(result.canFinalize, true);
    });
  });

  group('over-billing detection', () {
    test('billed > received is error', () {
      final result = svc.match(
        poTotal: 1180,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 8,
            billedQuantity: 10,
            billedRate: 100,
          ),
        ],
      );
      expect(result.isMatched, false);
      expect(result.hasErrors, true);
      expect(result.canFinalize, false);
      expect(result.errors.first.message, contains('exceeds received'));
    });
  });

  group('missing receipt detection', () {
    test('billed with zero receipt is error', () {
      final result = svc.match(
        poTotal: 1180,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 0,
            billedQuantity: 10,
            billedRate: 100,
          ),
        ],
      );
      expect(result.hasErrors, true);
      expect(
        result.errors.first.message,
        contains('no corresponding goods receipt'),
      );
    });
  });

  group('partial billing', () {
    test('under-billing is info, not error', () {
      final result = svc.match(
        poTotal: 1180,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 10,
            billedQuantity: 5,
            billedRate: 100,
          ),
        ],
      );
      expect(result.hasErrors, false);
      expect(result.canFinalize, true);
      expect(
        result.discrepancies.any((d) => d.message.contains('Partial')),
        true,
      );
    });
  });

  group('price variance', () {
    test('small variance within tolerance passes', () {
      final result = svc.match(
        poTotal: 1180,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 10,
            billedQuantity: 10,
            billedRate: 100.5,
          ),
        ],
      );
      expect(result.hasWarnings, false);
    });
    test('large variance is warning', () {
      final result = svc.match(
        poTotal: 1180,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 10,
            billedQuantity: 10,
            billedRate: 110,
          ),
        ],
      );
      expect(result.hasWarnings, true);
      expect(result.warnings.first.message, contains('Price variance'));
    });
  });

  group('total amount check', () {
    test('billed total exceeds PO total is error', () {
      final result = svc.match(
        poTotal: 1000,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 10,
            billedQuantity: 10,
            billedRate: 120,
          ),
        ],
      );
      expect(result.hasErrors, true);
      expect(
        result.errors.any((e) => e.message.contains('exceeds PO total')),
        true,
      );
    });
  });

  group('twoWayMatch', () {
    test('skips receipt validation', () {
      final result = svc.twoWayMatch(
        poTotal: 1180,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 0,
            billedQuantity: 10,
            billedRate: 100,
          ),
        ],
      );
      expect(result.hasErrors, false);
    });
  });

  group('MatchResult aggregation', () {
    test('totals computed correctly', () {
      final result = svc.match(
        poTotal: 2360,
        lines: [
          LineMatchInput(
            productId: 'p1',
            poQuantity: 10,
            poRate: 100,
            receivedQuantity: 10,
            billedQuantity: 10,
            billedRate: 100,
          ),
          LineMatchInput(
            productId: 'p2',
            poQuantity: 5,
            poRate: 200,
            receivedQuantity: 5,
            billedQuantity: 5,
            billedRate: 200,
          ),
        ],
      );
      expect(result.receivedQuantity, 15);
      expect(result.billedQuantity, 15);
      expect(result.billedAmount, 2000);
    });
  });
}
