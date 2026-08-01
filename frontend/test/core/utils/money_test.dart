/// Tests for the [Money] value object.
///
/// Every conversion path is tested including:
/// - Factory constructors (fromPaise, fromRupees, fromBackendMicros, parse)
/// - Backend micros round-trip (the non-standard 10,000 = ₹1 encoding)
/// - Arithmetic operators
/// - Edge cases: zero, negative, large, fractional rupees
library;

import 'package:apexbooks/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.fromRupees', () {
    test('₹1 = 100 paise', () {
      expect(Money.fromRupees(1).toPaise(), 100);
    });

    test('₹100 = 10000 paise', () {
      expect(Money.fromRupees(100).toPaise(), 10000);
    });

    test('₹0.50 = 50 paise', () {
      expect(Money.fromRupees(0.50).toPaise(), 50);
    });

    test('₹0.01 = 1 paise', () {
      expect(Money.fromRupees(0.01).toPaise(), 1);
    });

    test('negative ₹-25.75 = -2575 paise', () {
      expect(Money.fromRupees(-25.75).toPaise(), -2575);
    });

    test('large ₹9999999 = 999999900 paise', () {
      expect(Money.fromRupees(9999999).toPaise(), 999999900);
    });
  });

  group('Money.fromPaise', () {
    test('round-trip: paise → money → paise', () {
      final cases = [0, 1, 50, 100, 1850, -2575, 999999900];
      for (final p in cases) {
        expect(
          Money.fromPaise(p).toPaise(),
          p,
          reason: 'paise $p should round-trip',
        );
      }
    });

    test('toRupees converts correctly', () {
      expect(Money.fromPaise(100).toRupees(), 1.0);
      expect(Money.fromPaise(50).toRupees(), 0.5);
      expect(Money.fromPaise(1850).toRupees(), 18.5);
    });
  });

  group('Money.fromBackendMicros — non-standard 10,000 = ₹1', () {
    test('CONTRACT: 10,000 backend-micros = ₹1', () {
      // This test must fail if the backend changes their encoding convention.
      expect(Money.fromBackendMicros(10000).toRupees(), 1.0);
    });

    test('10,000 micros = 100 paise = ₹1', () {
      expect(Money.fromBackendMicros(10000).toPaise(), 100);
    });

    test('0 micros = 0 paise', () {
      expect(Money.fromBackendMicros(0).toPaise(), 0);
    });

    test('18,000 micros = 180 paise = ₹1.80', () {
      expect(Money.fromBackendMicros(18000).toPaise(), 180);
    });

    test('round-trip: paise → toBackendMicros → fromBackendMicros → paise', () {
      final cases = [0, 1, 50, 100, 1850, 10000, 100000];
      for (final p in cases) {
        final m = Money.fromPaise(p);
        final micros = m.toBackendMicros();
        final restored = Money.fromBackendMicros(micros);
        expect(
          restored.toPaise(),
          p,
          reason: 'paise $p should survive backend micros round-trip',
        );
      }
    });

    test('larger amounts round-trip', () {
      // ₹99,999 = 9,999,900 paise
      final original = Money.fromRupees(99999);
      final restored = Money.fromBackendMicros(original.toBackendMicros());
      expect(restored.toPaise(), original.toPaise());
    });
  });

  group('Money.parse', () {
    test('parses integer', () {
      expect(Money.parse(100).toRupees(), 100.0);
    });

    test('parses double', () {
      expect(Money.parse(18.5).toPaise(), 1850);
    });

    test('parses plain string', () {
      expect(Money.parse('100.50').toPaise(), 10050);
    });

    test('parses Indian comma-formatted string', () {
      expect(Money.parse('1,00,000.00').toPaise(), 10000000);
    });

    test('parses null as zero', () {
      expect(Money.parse(null).isZero, true);
    });

    test('parses empty string as zero', () {
      expect(Money.parse('').isZero, true);
    });

    test('throws on non-numeric string', () {
      expect(() => Money.parse('not-a-number'), throwsArgumentError);
    });
  });

  group('Money arithmetic', () {
    test('addition', () {
      expect((Money.fromPaise(100) + Money.fromPaise(50)).toPaise(), 150);
    });

    test('subtraction', () {
      expect((Money.fromPaise(100) - Money.fromPaise(30)).toPaise(), 70);
    });

    test('abs of negative', () {
      expect(Money.fromPaise(-100).abs().toPaise(), 100);
    });

    test('isZero', () {
      expect(Money.fromPaise(0).isZero, true);
      expect(Money.fromPaise(1).isZero, false);
    });

    test('isNegative', () {
      expect(Money.fromPaise(-1).isNegative, true);
      expect(Money.fromPaise(1).isNegative, false);
    });

    test('equality', () {
      expect(Money.fromPaise(100), Money.fromPaise(100));
      expect(Money.fromPaise(100) == Money.fromPaise(200), false);
    });

    test('comparison operators', () {
      final a = Money.fromRupees(10);
      final b = Money.fromRupees(20);
      expect(a < b, true);
      expect(b > a, true);
      expect(a <= a, true);
      expect(b >= b, true);
    });
  });
}
