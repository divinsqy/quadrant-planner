import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/database_paths.dart';
import '../database/user_data_schema.dart';
import '../export/json_data_exporter.dart';
import '../sync/field_merge.dart';
import '../sync/outbox_repository.dart';
import '../sync/credential_boundary.dart';
import 'backup_manifest.dart';

class BackupFailure implements Exception {
  final String code;
  final String? snapshotPath;
  const BackupFailure(this.code, {this.snapshotPath});
  @override
  String toString() => 'BackupFailure($code)';
}

class BackupService {
  final AppDatabase db;
  final Directory? snapshotDirectory;
  BackupService(this.db, {this.snapshotDirectory});
  Future<Map<String, Object?>> exportData() => db.transaction(() async {
    final data = await JsonDataExporter(db).data();
    data['local_evidence'] = {
      'conflicts':
          (await db
                  .customSelect('SELECT * FROM sync_conflicts ORDER BY rowid')
                  .get())
              .map((r) => r.data)
              .toList(),
      'tombstones':
          (await db
                  .customSelect('SELECT * FROM sync_tombstones ORDER BY rowid')
                  .get())
              .map((r) => r.data)
              .toList(),
      'migration':
          (await db
                  .customSelect('SELECT * FROM migration_state ORDER BY rowid')
                  .get())
              .map((r) => r.data)
              .toList(),
    };
    rejectCredentialFields(data);
    return data;
  });
  Future<Uint8List> bytes() async {
    final data = await exportData();
    final encoded = utf8.encode(jsonEncode(data));
    final tables = data['tables'] as Map;
    final manifest = BackupManifest(
      schemaVersion: db.schemaVersion,
      sha256: crypto.sha256.convert(encoded).toString(),
      createdAt: DateTime.now().toUtc().toIso8601String(),
      counts: tables.map(
        (key, value) => MapEntry(key as String, (value as List).length),
      ),
    );
    final archive = Archive()
      ..add(
        ArchiveFile(
          'manifest.json',
          0,
          utf8.encode(jsonEncode(manifest.toJson())),
        ),
      )
      ..add(ArchiveFile('user-data.json', encoded.length, encoded));
    // ArchiveFile uses the actual byte length, including Chinese UTF-8.
    archive.first.size = archive.first.readBytes()!.length;
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> createBackup(String destination) async {
    final file = File(destination);
    await file.parent.create(recursive: true);
    final temp = File('$destination.${const Uuid().v4()}.tmp');
    try {
      await temp.writeAsBytes(await bytes(), flush: true);
      await temp.rename(destination);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<(BackupManifest, Map<String, Object?>)> _inspect(String path) async {
    try {
      final file = File(path);
      if (await file.length() > 100 * 1024 * 1024) {
        throw const FormatException('Too large');
      }
      final archive = ZipDecoder().decodeBytes(
        await file.readAsBytes(),
        verify: true,
      );
      if (archive.length != 2 ||
          archive.any(
            (entry) =>
                !entry.isFile ||
                !['manifest.json', 'user-data.json'].contains(entry.name) ||
                entry.size > 100 * 1024 * 1024,
          )) {
        throw const FormatException('Invalid archive');
      }
      final manifest = BackupManifest.fromJson(
        jsonDecode(utf8.decode(archive.find('manifest.json')!.readBytes()!))
            as Map,
      );
      final dataBytes = archive.find('user-data.json')!.readBytes()!;
      if (manifest.schemaVersion != db.schemaVersion ||
          manifest.sha256 != crypto.sha256.convert(dataBytes).toString()) {
        throw const FormatException('Schema or hash mismatch');
      }
      final data = Map<String, Object?>.from(
        jsonDecode(utf8.decode(dataBytes)) as Map,
      );
      rejectCredentialFields(data);
      if (data['schema_version'] != db.schemaVersion ||
          data['format'] != 'quadrant-user-data') {
        throw const FormatException('Invalid data');
      }
      final schema = await UserDataSchema.load(db);
      final tables = data['tables'] as Map;
      if (tables.length != schema.tables.length) {
        throw const FormatException('Incomplete data');
      }
      for (final spec in schema.tables) {
        final rows = tables[spec.name] as List;
        final ids = <String>{};
        if (manifest.counts[spec.name] != rows.length) {
          throw const FormatException('Count mismatch');
        }
        for (final row in rows) {
          final value = Map<String, Object?>.from(row as Map);
          schema.validate(spec.name, value);
          if (!ids.add(spec.idOf(value))) {
            throw const FormatException('Duplicate entity');
          }
        }
      }
      return (manifest, data);
    } catch (_) {
      throw const BackupFailure('invalid_backup');
    }
  }

  Future<BackupManifest> inspectBackup(String path) async =>
      (await _inspect(path)).$1;
  Future<String> restoreBackup(String path) => db.transaction(() async {
    final directory =
        snapshotDirectory ??
        Directory(
          p.join(
            p.dirname((await DatabasePaths.current()).v1DatabasePath),
            'backups',
          ),
        );
    final snapshot = p.join(
      directory.path,
      'pre-restore-${DateTime.now().toUtc().microsecondsSinceEpoch}-${const Uuid().v4()}.qpb',
    );
    await createBackup(
      snapshot,
    ); // Required even if the selected file is corrupt.
    try {
      final (_, data) = await _inspect(path);
      final schema = await UserDataSchema.load(db);
      final tables = data['tables'] as Map;
      final outbox = OutboxRepository(db);
      final before = <String, List<Map<String, Object?>>>{};
      for (final spec in schema.tables) {
        before[spec.name] =
            (await db
                    .customSelect(
                      'SELECT ${spec.columns.join(',')} FROM ${spec.name}',
                    )
                    .get())
                .map((r) => r.data)
                .toList();
      }
      await outbox.withoutCapture(() async {
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        await outbox.disable();
        // Existing network receipts remain frozen but cannot be replayed after
        // the user deliberately replaces local data. Cloud reconciliation is
        // resumed explicitly; shadow revisions remain available for conflicts.
        await db.customUpdate(
          "UPDATE sync_outbox SET status='superseded' WHERE status IN ('pending','sending','failed')",
          updates: {db.syncOutbox},
        );
        for (final spec in schema.tables) {
          final restoredIds = (tables[spec.name] as List)
              .map((row) => spec.idOf(Map<String, Object?>.from(row as Map)))
              .toSet();
          for (final row in before[spec.name]!) {
            if (!restoredIds.contains(spec.idOf(row))) {
              await db.customStatement(
                'INSERT INTO sync_tombstones(entity_kind,entity_id,deleted_at) VALUES(?,?,?) ON CONFLICT(entity_kind,entity_id) DO NOTHING',
                [
                  spec.name,
                  spec.idOf(row),
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
                ],
              );
            }
          }
        }
        for (final spec in schema.tables.reversed) {
          await db.customUpdate(
            'DELETE FROM ${spec.name}',
            updates: schema.readsFrom,
          );
        }
        for (final spec in schema.tables) {
          for (final value in tables[spec.name] as List) {
            await schema.write(
              spec.name,
              Map<String, Object?>.from(value as Map),
            );
          }
        }
        await db.customUpdate(
          'DELETE FROM sync_conflicts',
          updates: {db.syncConflicts},
        );
        final evidence = data['local_evidence'] as Map? ?? {};
        await db.customUpdate(
          'DELETE FROM migration_state',
          updates: {db.migrationState},
        );
        for (final value in evidence['migration'] as List? ?? []) {
          final row = value as Map;
          final columns = [
            'id',
            'source_path',
            'source_hash',
            'migrated_at',
            'imported_counts_json',
            'skipped_json',
            'success',
          ];
          await db.customInsert(
            'INSERT INTO migration_state(${columns.join(',')}) VALUES(${columns.map((_) => '?').join(',')})',
            variables: columns.map((key) => Variable(row[key])).toList(),
            updates: {db.migrationState},
          );
        }
        for (final value in evidence['conflicts'] as List? ?? []) {
          final row = Map<String, Object?>.from(value as Map);
          final columns = [
            'id',
            'entity_kind',
            'entity_id',
            'field',
            'base_json',
            'local_json',
            'remote_json',
            'created_at',
            'resolved_at',
          ];
          await db.customInsert(
            'INSERT INTO sync_conflicts(${columns.join(',')}) VALUES(${columns.map((_) => '?').join(',')})',
            variables: columns.map((key) => Variable(row[key])).toList(),
            updates: {db.syncConflicts},
          );
        }
        // Keep current durable tombstones as well as archived ones, then remove
        // them only for live rows explicitly restored by this operation.
        for (final value in evidence['tombstones'] as List? ?? []) {
          final row = value as Map;
          await db.customStatement(
            'INSERT INTO sync_tombstones(entity_kind,entity_id,deleted_at) VALUES(?,?,?) ON CONFLICT(entity_kind,entity_id) DO NOTHING',
            [row['entity_kind'], row['entity_id'], row['deleted_at']],
          );
        }
        for (final spec in schema.tables) {
          for (final value in tables[spec.name] as List) {
            final row = Map<String, Object?>.from(value as Map);
            if (!isDeleted(row)) {
              await db.customStatement(
                'INSERT OR IGNORE INTO sync_restore_intents(entity_kind,entity_id) SELECT ?,? WHERE EXISTS(SELECT 1 FROM sync_tombstones WHERE entity_kind=? AND entity_id=?)',
                [spec.name, spec.idOf(row), spec.name, spec.idOf(row)],
              );
              await db.customStatement(
                'DELETE FROM sync_tombstones WHERE entity_kind=? AND entity_id=?',
                [spec.name, spec.idOf(row)],
              );
            } else {
              await db.customStatement(
                'INSERT INTO sync_tombstones(entity_kind,entity_id,deleted_at) VALUES(?,?,?) ON CONFLICT(entity_kind,entity_id) DO NOTHING',
                [
                  spec.name,
                  spec.idOf(row),
                  row['deleted_at'] ??
                      DateTime.now().millisecondsSinceEpoch ~/ 1000,
                ],
              );
            }
          }
        }
        if ((await db.customSelect('PRAGMA foreign_key_check').get())
            .isNotEmpty) {
          throw const FormatException('Invalid references');
        }
      }, restoring: true);
      return snapshot;
    } catch (_) {
      throw BackupFailure('restore_failed', snapshotPath: snapshot);
    }
  });
}
