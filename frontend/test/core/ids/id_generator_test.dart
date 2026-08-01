/// Tests for [IdGenerator].
///
/// Idempotency keys must be stable — the same inputs always produce the same
/// output.  This is critical: a changed key on retry would break idempotency
/// guarantees and could create duplicate server records.
library;

import 'package:apexbooks/core/ids/id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdGenerator.newId', () {
    test('returns a valid UUID v4 format', () {
      final id = IdGenerator.newId();
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(
        uuidPattern.hasMatch(id),
        true,
        reason: 'newId() must return a UUID v4: $id',
      );
    });

    test('returns a unique value each call', () {
      final ids = {for (var i = 0; i < 100; i++) IdGenerator.newId()};
      expect(ids.length, 100);
    });
  });

  group('IdGenerator.createKey', () {
    test('is deterministic', () {
      const entityType = 'journal';
      const localId = '550e8400-e29b-41d4-a716-446655440000';
      final k1 = IdGenerator.createKey(entityType, localId);
      final k2 = IdGenerator.createKey(entityType, localId);
      expect(k1, k2);
    });

    test('format is entityType:create:localId', () {
      expect(
        IdGenerator.createKey('journal', 'abc-123'),
        'journal:create:abc-123',
      );
    });
  });

  group('IdGenerator.updateKey', () {
    test('includes revision so different revisions produce different keys', () {
      const localId = 'abc-123';
      final k1 = IdGenerator.updateKey('invoice', localId, 1);
      final k2 = IdGenerator.updateKey('invoice', localId, 2);
      expect(k1, isNot(k2));
    });

    test('format is entityType:update:localId:revision', () {
      expect(
        IdGenerator.updateKey('invoice', 'abc-123', 3),
        'invoice:update:abc-123:3',
      );
    });
  });

  group('IdGenerator.actionKey', () {
    test('format is entityType:action:localId', () {
      expect(
        IdGenerator.actionKey('journal', 'reverse', 'abc-123'),
        'journal:reverse:abc-123',
      );
    });
  });
}
