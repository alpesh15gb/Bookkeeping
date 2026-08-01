/// Tests for [SyncStatus] and [SyncSummary].
library;

import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncStatus', () {
    test('isPending only for pending', () {
      expect(SyncStatus.pending.isPending, true);
      expect(SyncStatus.synced.isPending, false);
      expect(SyncStatus.failed.isPending, false);
      expect(SyncStatus.conflict.isPending, false);
      expect(SyncStatus.localOnly.isPending, false);
      expect(SyncStatus.syncing.isPending, false);
    });

    test('requiresAttention for failed and conflict only', () {
      expect(SyncStatus.failed.requiresAttention, true);
      expect(SyncStatus.conflict.requiresAttention, true);
      expect(SyncStatus.synced.requiresAttention, false);
      expect(SyncStatus.pending.requiresAttention, false);
    });

    test('isSynced only for synced', () {
      expect(SyncStatus.synced.isSynced, true);
      for (final s in SyncStatus.values.where((s) => s != SyncStatus.synced)) {
        expect(s.isSynced, false);
      }
    });

    test('label is a non-empty string for all values', () {
      for (final s in SyncStatus.values) {
        expect(s.label.isNotEmpty, true);
      }
    });
  });

  group('SyncSummary.statusLabel', () {
    test('active sync → "Syncing…"', () {
      const s = SyncSummary(
        pendingCount: 3,
        failedCount: 0,
        conflictCount: 0,
        lastSyncedAt: null,
        isActive: true,
        isOnline: true,
      );
      expect(s.statusLabel, 'Syncing…');
    });

    test('offline → "Offline"', () {
      const s = SyncSummary(
        pendingCount: 0,
        failedCount: 0,
        conflictCount: 0,
        lastSyncedAt: null,
        isActive: false,
        isOnline: false,
      );
      expect(s.statusLabel, 'Offline');
    });

    test('conflict → mentions conflict', () {
      const s = SyncSummary(
        pendingCount: 0,
        failedCount: 0,
        conflictCount: 1,
        lastSyncedAt: null,
        isActive: false,
        isOnline: true,
      );
      expect(s.statusLabel.toLowerCase(), contains('conflict'));
    });

    test('up to date', () {
      final s = SyncSummary(
        pendingCount: 0,
        failedCount: 0,
        conflictCount: 0,
        lastSyncedAt: DateTime.now(),
        isActive: false,
        isOnline: true,
      );
      expect(s.statusLabel, 'Up to date');
    });

    test('pending shows count', () {
      const s = SyncSummary(
        pendingCount: 5,
        failedCount: 0,
        conflictCount: 0,
        lastSyncedAt: null,
        isActive: false,
        isOnline: true,
      );
      expect(s.statusLabel, contains('5'));
    });
  });
}
