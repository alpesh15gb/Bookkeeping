library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

const _databaseName = 'apexbooks_encrypted';
const _legacyDatabaseName = 'apexbooks.sqlite';

String _escapeSql(String value) => value.replaceAll("'", "''");

bool _hasCipher(CommonDatabase database) =>
    database.select('PRAGMA cipher;').isNotEmpty;

/// Converts the previous plaintext Drift file to an encrypted copy without
/// removing the source until the encrypted copy has been opened successfully.
Future<void> prepareEncryptedNativeDatabase(String key) async {
  final directory = await getApplicationDocumentsDirectory();
  final legacy = File(p.join(directory.path, _legacyDatabaseName));
  final encrypted = File(p.join(directory.path, '$_databaseName.sqlite'));
  if (await encrypted.exists() || !await legacy.exists()) return;

  final temporary = File('${encrypted.path}.tmp');
  if (await temporary.exists()) await temporary.delete();
  final escapedTemporaryPath = _escapeSql(temporary.path);
  final escapedKey = _escapeSql(key);

  try {
    final plaintext = sqlite3.open(legacy.path);
    try {
      if (!_hasCipher(plaintext)) {
        throw StateError(
          'The native SQLite build does not provide database encryption.',
        );
      }
      plaintext.execute("VACUUM INTO '$escapedTemporaryPath';");
    } finally {
      plaintext.close();
    }

    final toEncrypt = sqlite3.open(temporary.path);
    try {
      toEncrypt.execute("PRAGMA rekey = '$escapedKey';");
    } finally {
      toEncrypt.close();
    }

    final verification = sqlite3.open(temporary.path);
    try {
      verification.execute("PRAGMA key = '$escapedKey';");
      verification.select('SELECT count(*) FROM sqlite_master;');
    } finally {
      verification.close();
    }

    await temporary.rename(encrypted.path);
    await legacy.delete();
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${legacy.path}$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}

QueryExecutor openEncryptedNativeDatabase(String key) {
  final escapedKey = _escapeSql(key);
  return driftDatabase(
    name: _databaseName,
    native: DriftNativeOptions(
      shareAcrossIsolates: true,
      setup: (database) {
        if (!_hasCipher(database)) {
          throw StateError(
            'Encrypted SQLite is unavailable in this native build.',
          );
        }
        database.execute("PRAGMA key = '$escapedKey';");
        database.select('SELECT count(*) FROM sqlite_master;');
      },
    ),
  );
}
