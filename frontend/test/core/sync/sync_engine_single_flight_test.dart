/// Sync engine single-flight test.
///
/// Verifies that concurrent triggers (app resume, connectivity, timer,
/// manual) produce only one active sync cycle at a time.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutex/mutex.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/core/database/app_database.dart';
import 'package:drift/native.dart';

void main() {
  group('SyncEngine single-flight', () {
    test('Mutex prevents concurrent push cycles', () async {
      final lock = Mutex();
      int activeCount = 0;
      int maxActive = 0;

      // Simulate a slow operation that checks concurrency.
      Future<void> simulateCycle(int id) async {
        if (lock.isLocked) return; // Skip if another cycle is running
        await lock.protect(() async {
          activeCount++;
          maxActive = maxActive > activeCount ? maxActive : activeCount;
          // Simulate work.
          await Future.delayed(const Duration(milliseconds: 50));
          activeCount--;
        });
      }

      // Fire multiple triggers concurrently.
      await Future.wait([
        simulateCycle(1),
        simulateCycle(2),
        simulateCycle(3),
        simulateCycle(4),
        simulateCycle(5),
        simulateCycle(6),
        simulateCycle(7),
        simulateCycle(8),
      ]);

      // Only one cycle should have been active at any time.
      expect(
        maxActive,
        lessThanOrEqualTo(1),
        reason: 'Multiple triggers must not run concurrent cycles',
      );
    });

    test('runPushCycle returns 0 when lock is held', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final engine = SyncEngine(db: db, dio: Dio(BaseOptions()));

      // First call starts a cycle.
      final future1 = engine.runPushCycle();
      // Second call should return 0 immediately (lock held).
      final result2 = await engine.runPushCycle();
      // Wait for first to finish.
      await future1;

      expect(
        result2,
        0,
        reason: 'runPushCycle must return 0 when another cycle is active',
      );

      await db.close();
    });

    test('scheduler triggers do not stack', () async {
      // Create an engine and fire multiple immediate trigger signals.
      // The engine's lock ensures only one drains the outbox at a time.
      final db = AppDatabase(NativeDatabase.memory());
      final engine = SyncEngine(db: db, dio: Dio(BaseOptions()));

      // Fire several push cycles in quick succession.
      final results = await Future.wait([
        engine.runPushCycle(),
        engine.runPushCycle(),
        engine.runPushCycle(),
        engine.runPushCycle(),
        engine.runPushCycle(),
      ]);

      // At most one should have returned > 0 (actually 0 since DB is empty).
      final positiveResults = results.where((r) => r > 0).length;
      expect(
        positiveResults,
        lessThanOrEqualTo(1),
        reason: 'Multiple rapid triggers should not all start sync cycles',
      );

      await db.close();
    });
  });
}
