/// Stable, globally unique identifier generation for offline-first entities.
///
/// Every locally created entity receives a UUID v4 as its [localId].  This is
/// the stable client-side identity used in all local FK relationships.  A
/// [remoteId] may be added after the entity is successfully synced to the
/// server.
///
/// Idempotency keys encode the operation intent in a deterministic string so
/// that retried sync operations never create duplicate server records.
library;

import 'package:uuid/uuid.dart';

class IdGenerator {
  IdGenerator._();

  static const _uuid = Uuid();

  // ── Entity IDs ────────────────────────────────────────────────────────────

  /// Returns a new UUID v4 suitable as a local entity ID.
  static String newId() => _uuid.v4();

  // ── Idempotency keys ──────────────────────────────────────────────────────

  /// Stable key for a *create* operation.
  ///
  /// Encoded as `<entityType>:create:<localId>`.
  ///
  /// Reuse this exact key on every retry so the server deduplicates safely.
  static String createKey(String entityType, String localId) =>
      '$entityType:create:$localId';

  /// Stable key for an *update* at a particular revision.
  ///
  /// Encoded as `<entityType>:update:<localId>:<localRevision>`.
  ///
  /// A new revision produces a new key, so retries of the same edit are
  /// idempotent but a later edit gets a distinct key.
  static String updateKey(
    String entityType,
    String localId,
    int localRevision,
  ) => '$entityType:update:$localId:$localRevision';

  /// Stable key for a *delete* operation.
  static String deleteKey(String entityType, String localId) =>
      '$entityType:delete:$localId';

  /// Stable key for a domain action (post, finalize, reverse, reconcile, …).
  ///
  /// Encoded as `<entityType>:<action>:<localId>`.
  static String actionKey(String entityType, String action, String localId) =>
      '$entityType:$action:$localId';

  /// Stable key for an action that is keyed on the action UUID itself.
  ///
  /// Use this when an action (e.g. *send invoice*) is represented as its own
  /// entity with a [actionId], not bound to a single revision of the parent.
  static String actionInstanceKey(
    String entityType,
    String action,
    String localId,
    String actionId,
  ) => '$entityType:$action:$localId:$actionId';
}
