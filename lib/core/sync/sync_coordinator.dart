import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../database/user_data_schema.dart';
import 'conflict_repository.dart';
import 'field_merge.dart';
import 'outbox_repository.dart';
import 'secure_session_store.dart';
import 'supabase_sync_client.dart';

enum SyncStatus { disabled, authRequired, synced, syncing, pending, conflict }

class SyncCoordinator extends ChangeNotifier {
  final AppDatabase db;
  final SecureSessionStore sessions;
  final SyncTransport transport;
  late final outbox = OutboxRepository(db);
  late final conflicts = ConflictRepository(db);
  SyncStatus status = SyncStatus.disabled;
  String? errorCode;
  int pendingCount = 0, conflictCount = 0;
  Future<void>? _running;
  StreamSubscription? _subscription;
  Timer? _timer, _debounce;
  bool _disposed = false;
  bool _maintenance = false;
  SyncCoordinator({
    required this.db,
    required this.sessions,
    required this.transport,
  });
  bool get configured => transport.configured;
  void _set(SyncStatus value) {
    status = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (!configured || _disposed || _subscription != null) return;
    try {
      final schema = await UserDataSchema.load(db);
      if (_disposed) return;
      _subscription = db
          .customSelect(
            'SELECT COUNT(*) AS total FROM sync_outbox',
            readsFrom: {...schema.readsFrom, db.syncOutbox},
          )
          .watch()
          .listen(
            (_) {
              if (_running != null || _disposed) return;
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 500),
                () => syncOnce(),
              );
            },
            onError: (Object error, StackTrace stack) {
              if (!_disposed) {
                errorCode = 'network';
                _set(SyncStatus.pending);
              }
            },
          );
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => syncOnce());
      await syncOnce();
    } catch (_) {
      if (!_disposed) {
        errorCode = 'network';
        _set(SyncStatus.pending);
      }
    }
  }

  Future<void> requestOtp(String email) => transport.requestOtp(email);
  Future<void> signIn(String email, String code) async {
    final session = await transport.verifyOtp(email, code);
    final bound = await outbox.boundUser;
    if (bound != null && bound != session.userId) {
      throw const SyncFailure('account_mismatch');
    }
    // Tokens are durable before account activation; neither is part of a normal
    // task edit, and a failed secure write leaves the workspace local.
    await sessions.write(session);
    await outbox.activate(session.userId);
    _set(SyncStatus.pending);
  }

  Future<void> signOut() async {
    if (_running != null) await _running;
    await outbox.disable();
    await sessions.clear();
    errorCode = null;
    _set(SyncStatus.disabled);
  }

  Future<void> resume() async {
    final session = await sessions.read();
    if (session == null) {
      _set(SyncStatus.authRequired);
      return;
    }
    await outbox.activate(session.userId);
    await syncOnce();
  }

  Future<T> withSyncPaused<T>(Future<T> Function() action) async {
    _maintenance = true;
    try {
      if (_running != null) await _running;
      return await action();
    } finally {
      _maintenance = false;
      await _counts();
      _set(await outbox.enabled ? SyncStatus.pending : SyncStatus.disabled);
    }
  }

  Future<T> _authorized<T>(Future<T> Function(AuthSession) request) async {
    var session = await sessions.read();
    if (session == null) throw const SyncFailure('auth_required');
    if (session.expiresAt.isBefore(
      DateTime.now().add(const Duration(minutes: 1)),
    )) {
      session = await transport.refresh(session);
      await sessions.write(session);
    }
    try {
      return await request(session);
    } on SyncFailure catch (error) {
      if (error.code != 'auth_required') rethrow;
      session = await transport.refresh(session);
      await sessions.write(session);
      return request(session);
    }
  }

  Future<void> syncOnce() {
    if (_disposed || _maintenance) return Future.value();
    return _running ??= _sync().whenComplete(() => _running = null);
  }

  Future<void> _counts() async {
    pendingCount = (await outbox.pending()).length;
    conflictCount = (await conflicts.unresolved()).length;
    pendingCount +=
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS total FROM sync_shadow WHERE pending_apply=1',
                )
                .getSingle())
            .read<int>('total');
  }

  Future<void> _sync() async {
    try {
      if (!configured) {
        await _counts();
        _set(SyncStatus.disabled);
        return;
      }
      final session = await sessions.read();
      if (session == null) {
        await _counts();
        _set(
          await outbox.boundUser == null
              ? SyncStatus.disabled
              : SyncStatus.authRequired,
        );
        return;
      }
      if (!await outbox.enabled) {
        _set(SyncStatus.disabled);
        return;
      }
      if (await outbox.boundUser != session.userId) {
        throw const SyncFailure('account_mismatch');
      }
      _set(SyncStatus.syncing);
      errorCode = null;
      await db.transaction(_retryDeferred);
      for (final queued in await outbox.pending()) {
        if (_disposed) return;
        if ((await conflicts.unresolved()).any(
          (c) =>
              c.entityKind == queued.entityKind &&
              c.entityId == queued.entityId,
        )) {
          continue;
        }
        final deferred = await db
            .customSelect(
              'SELECT 1 AS present FROM sync_shadow WHERE entity_kind=? AND entity_id=? AND pending_apply=1',
              variables: [
                Variable(queued.entityKind),
                Variable(queued.entityId),
              ],
            )
            .getSingleOrNull();
        if (deferred != null) continue;
        // A preceding receipt/pull may have superseded this snapshot item.
        if (!(await outbox.pending()).any(
          (op) => op.operationId == queued.operationId,
        )) {
          continue;
        }
        final op = await outbox.beginAttempt(queued.operationId);
        try {
          final result = await _authorized(
            (session) => transport.push(op, session),
          );
          if (_disposed) return;
          if (result.entity.kind != op.entityKind ||
              result.entity.id != op.entityId) {
            throw const SyncFailure('invalid_remote');
          }
          await db.transaction(() async {
            await outbox.markApplied(op.operationId);
            await _ingest(
              result.entity,
              acknowledgedBase: result.accepted ? op.payload : null,
            );
          });
        } catch (_) {
          if (_disposed) return;
          await outbox.markFailed(op.operationId, 'network');
          rethrow;
        }
      }
      var cursor =
          (await (db.select(
            db.syncState,
          )..where((r) => r.id.equals('default'))).getSingleOrNull())?.cursor ??
          0;
      for (var pages = 0; pages < 1000; pages++) {
        final page = await _authorized(
          (session) => transport.pull(cursor, session),
        );
        if (_disposed) return;
        if (page.cursor < cursor || (page.hasMore && page.cursor == cursor)) {
          throw const SyncFailure('invalid_remote');
        }
        await db.transaction(() async {
          for (final change in page.changes) {
            await _ingest(change);
          }
          await _retryDeferred();
          await db
              .into(db.syncState)
              .insertOnConflictUpdate(
                SyncStateCompanion.insert(
                  id: 'default',
                  cursor: Value(page.cursor),
                  status: const Value('synced'),
                  updatedAt: DateTime.now().toUtc(),
                ),
              );
        });
        cursor = page.cursor;
        if (!page.hasMore) break;
        if (pages == 999) throw const SyncFailure('invalid_remote');
      }
      await _counts();
      _set(
        conflictCount > 0
            ? SyncStatus.conflict
            : pendingCount > 0
            ? SyncStatus.pending
            : SyncStatus.synced,
      );
    } catch (error) {
      if (_disposed) return;
      errorCode = error is SyncFailure ? error.code : 'network';
      await _counts();
      _set(
        conflictCount > 0
            ? SyncStatus.conflict
            : errorCode == 'auth_required'
            ? SyncStatus.authRequired
            : SyncStatus.pending,
      );
    }
  }

  Future<void> _ingest(
    RemoteEntity entity, {
    Map<String, Object?>? acknowledgedBase,
  }) async {
    final schema = await UserDataSchema.load(db);
    schema.validate(entity.kind, entity.payload);
    if (schema.table(entity.kind).idOf(entity.payload) != entity.id ||
        entity.revision <= 0) {
      throw const SyncFailure('invalid_remote');
    }
    final previous = await db
        .customSelect(
          'SELECT * FROM sync_shadow WHERE entity_kind=? AND entity_id=?',
          variables: [Variable(entity.kind), Variable(entity.id)],
        )
        .getSingleOrNull();
    if (previous != null && previous.read<int>('revision') >= entity.revision) {
      return;
    }
    if (entity.restored) {
      await db.customStatement(
        'DELETE FROM sync_tombstones WHERE entity_kind=? AND entity_id=?',
        [entity.kind, entity.id],
      );
    }
    if (entity.restored ||
        acknowledgedBase != null && !isDeleted(entity.payload)) {
      await db.customStatement(
        'DELETE FROM sync_restore_intents WHERE entity_kind=? AND entity_id=?',
        [entity.kind, entity.id],
      );
    }
    final base =
        acknowledgedBase ??
        (previous == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(
                jsonDecode(previous.read<String>('payload_json')) as Map,
              ));
    final actualLocal = await schema.read(entity.kind, entity.id);
    var local = actualLocal;
    if (previous?.read<int>('pending_apply') == 1 && local != null) {
      final before = Map<String, Object?>.from(
        jsonDecode(previous!.readNullable<String>('apply_before_json') ?? '{}')
            as Map,
      );
      final desired = Map<String, Object?>.from(
        jsonDecode(
          previous.readNullable<String>('apply_json') ??
              previous.read<String>('payload_json'),
        ) as Map,
      );
      final effective = mergeEntity(before, local, desired);
      for (final conflict in effective.conflicts) {
        await conflicts.record(entity.kind, entity.id, conflict);
      }
      local = effective.payload;
    }
    final tombstone = await db
        .customSelect(
          'SELECT deleted_at FROM sync_tombstones WHERE entity_kind=? AND entity_id=?',
          variables: [Variable(entity.kind), Variable(entity.id)],
        )
        .getSingleOrNull();
    if (tombstone != null && !isDeleted(entity.payload)) {
      local = {
        ...(local ?? entity.payload),
        if (schema.table(entity.kind).columns.contains('deleted_at'))
          'deleted_at': tombstone.read<int>('deleted_at')
        else
          '_deleted': 1,
      };
    }
    // A server-confirmed explicit restore may replace a previously deleted row.
    final restoreIntent = await db
        .customSelect(
          'SELECT 1 AS present FROM sync_restore_intents WHERE entity_kind=? AND entity_id=?',
          variables: [Variable(entity.kind), Variable(entity.id)],
        )
        .getSingleOrNull();
    final result =
        restoreIntent != null &&
            local != null &&
            !isDeleted(local) &&
            isDeleted(entity.payload)
        ? MergeResult(local, [])
        : local == null || entity.restored && isDeleted(local)
        ? MergeResult(entity.payload, [])
        : mergeEntity(base, local, entity.payload);
    for (final conflict in result.conflicts) {
      await conflicts.record(entity.kind, entity.id, conflict);
    }
    await db.customStatement(
      'INSERT INTO sync_shadow(entity_kind,entity_id,revision,payload_json,pending_apply,apply_json,apply_before_json) VALUES(?,?,?,?,1,?,?) ON CONFLICT(entity_kind,entity_id) DO UPDATE SET revision=excluded.revision,payload_json=excluded.payload_json,pending_apply=1,apply_json=excluded.apply_json,apply_before_json=excluded.apply_before_json',
      [
        entity.kind,
        entity.id,
        entity.revision,
        jsonEncode(entity.payload),
        jsonEncode(result.payload),
        jsonEncode(actualLocal ?? {}),
      ],
    );
    if (isDeleted(result.payload)) {
      await db.customStatement(
        'INSERT INTO sync_tombstones(entity_kind,entity_id,deleted_at) VALUES(?,?,?) ON CONFLICT(entity_kind,entity_id) DO NOTHING',
        [
          entity.kind,
          entity.id,
          result.payload['deleted_at'] ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ],
      );
    }
    try {
      await outbox.withoutCapture(
        () => schema.write(entity.kind, result.payload),
      );
    } on DataInvariantFailure {
      await _invariantConflict(
        entity.kind,
        entity.id,
        actualLocal,
        result.payload,
      );
      return;
    } catch (_) {
      // Missing parents or a second active Focus session are retried from the
      // durable shadow. The pull cursor can advance without losing the row.
      return;
    }
    await _finishApplied(
      entity.kind,
      entity.id,
      result.payload,
      entity.payload,
    );
  }

  Future<void> _invariantConflict(
    String kind,
    String id,
    Map<String, Object?>? local,
    Map<String, Object?> remote,
  ) async {
    await conflicts.record(
      kind,
      id,
      FieldConflict('_invariant', null, local, remote),
    );
    await db.customStatement(
      'UPDATE sync_shadow SET pending_apply=0 WHERE entity_kind=? AND entity_id=?',
      [kind, id],
    );
  }

  Future<void> _finishApplied(
    String kind,
    String id,
    Map<String, Object?> payload,
    Map<String, Object?> remote,
  ) async {
    await db.customStatement(
      'UPDATE sync_shadow SET pending_apply=0,apply_before_json=NULL,apply_json=NULL WHERE entity_kind=? AND entity_id=?',
      [kind, id],
    );
    await outbox.supersede(kind, id);
    if ((await conflicts.unresolved()).any(
      (c) => c.entityKind == kind && c.entityId == id,
    )) {
      return;
    }
    if (!sameValue(payload, remote)) {
      final restore = await db
          .customSelect(
            'SELECT 1 AS present FROM sync_restore_intents WHERE entity_kind=? AND entity_id=?',
            variables: [Variable(kind), Variable(id)],
          )
          .getSingleOrNull();
      await outbox.enqueue(kind, id, payload, explicitRestore: restore != null);
    }
  }

  Future<void> _retryDeferred() async {
    final schema = await UserDataSchema.load(db);
    for (final spec in schema.tables) {
      for (final row
          in await db
              .customSelect(
                'SELECT * FROM sync_shadow WHERE pending_apply=1 AND entity_kind=?',
                variables: [Variable(spec.name)],
              )
              .get()) {
        var payload = Map<String, Object?>.from(
          jsonDecode(
            row.readNullable<String>('apply_json') ??
                row.read<String>('payload_json'),
          ) as Map,
        );
        final id = row.read<String>('entity_id');
        final current = await schema.read(spec.name, id);
        final before = Map<String, Object?>.from(
          jsonDecode(row.readNullable<String>('apply_before_json') ?? '{}')
              as Map,
        );
        final restore = await db
            .customSelect(
              'SELECT 1 AS present FROM sync_restore_intents WHERE entity_kind=? AND entity_id=?',
              variables: [Variable(spec.name), Variable(id)],
            )
            .getSingleOrNull();
        final merged = current == null
            ? MergeResult(payload, [])
            : restore != null && !isDeleted(current) && isDeleted(payload)
            ? MergeResult(current, [])
            : mergeEntity(before, current, payload);
        payload = merged.payload;
        for (final conflict in merged.conflicts) {
          await conflicts.record(spec.name, id, conflict);
        }
        final tombstone = await db
            .customSelect(
              'SELECT 1 AS present FROM sync_tombstones WHERE entity_kind=? AND entity_id=?',
              variables: [Variable(spec.name), Variable(id)],
            )
            .getSingleOrNull();
        if (tombstone != null && !isDeleted(payload) && restore == null) {
          continue;
        }
        try {
          await outbox.withoutCapture(() => schema.write(spec.name, payload));
          await _finishApplied(
            spec.name,
            id,
            payload,
            Map<String, Object?>.from(
              jsonDecode(row.read<String>('payload_json')) as Map,
            ),
          );
        } on DataInvariantFailure {
          await _invariantConflict(spec.name, id, current, payload);
        } catch (_) {
          /* Preserve for the next pull/restart. */
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _timer?.cancel();
    _debounce?.cancel();
    transport.close();
    super.dispose();
  }
}
