import 'dart:async';

import 'package:quadrant_planner/core/sync/secure_session_store.dart';
import 'package:quadrant_planner/core/sync/supabase_sync_client.dart';
import 'package:quadrant_planner/core/sync/sync_operation.dart';
import 'package:quadrant_planner/core/sync/field_merge.dart';

class MemorySessions implements SecureSessionStore {
  AuthSession? value;
  @override
  Future<AuthSession?> read() async => value;
  @override
  Future<void> write(AuthSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FakeCloud implements SyncTransport {
  @override
  bool get configured => true;
  bool fail = false;
  Completer<void>? gate;
  final receipts = <String, PushResult>{};
  final entities = <String, RemoteEntity>{};
  final changes = <RemoteEntity>[];
  int pushCalls = 0;
  @override
  Future<void> requestOtp(String email) async {}
  @override
  Future<AuthSession> verifyOtp(String email, String code) async => AuthSession(
    userId: 'u',
    accessToken: 'SECRET_ACCESS',
    refreshToken: 'SECRET_REFRESH',
    expiresAt: DateTime.utc(2100),
  );
  @override
  Future<AuthSession> refresh(AuthSession session) async => session;
  @override
  Future<PushResult> push(SyncOperation op, AuthSession session) async {
    pushCalls++;
    if (gate != null) await gate!.future;
    if (fail) throw const SyncFailure('network');
    if (receipts.containsKey(op.operationId)) return receipts[op.operationId]!;
    final key = '${op.entityKind}/${op.entityId}';
    final current = entities[key];
    if (current != null &&
        (current.revision != op.baseRevision ||
            isDeleted(current.payload) &&
                !isDeleted(op.payload) &&
                !op.explicitRestore)) {
      return receipts[op.operationId] = PushResult(
        accepted: false,
        entity: current,
      );
    }
    final entity = RemoteEntity(
      kind: op.entityKind,
      id: op.entityId,
      revision: (current?.revision ?? 0) + 1,
      payload: op.payload,
      sequence: changes.length + 1,
      restored:
          current != null &&
          isDeleted(current.payload) &&
          !isDeleted(op.payload) &&
          op.explicitRestore,
    );
    entities[key] = entity;
    changes.add(entity);
    return receipts[op.operationId] = PushResult(
      accepted: true,
      entity: entity,
    );
  }

  @override
  Future<PullPage> pull(int cursor, AuthSession session) async => PullPage(
    changes: changes.where((e) => e.sequence > cursor).toList(),
    cursor: changes.length,
    hasMore: false,
  );
  @override
  void close() {}
}
