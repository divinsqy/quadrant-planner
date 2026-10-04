import 'dart:convert';

import 'package:http/http.dart' as http;

import 'secure_session_store.dart';
import 'sync_operation.dart';

class SyncFailure implements Exception {
  final String code;
  const SyncFailure(this.code);
  @override
  String toString() => 'SyncFailure($code)';
}

class RemoteEntity {
  final String kind, id;
  final int revision, sequence;
  final Map<String, Object?> payload;
  final bool restored;
  const RemoteEntity({
    required this.kind,
    required this.id,
    required this.revision,
    required this.payload,
    this.sequence = 0,
    this.restored = false,
  });
  factory RemoteEntity.fromJson(Map value) => RemoteEntity(
    kind: value['entity_kind'] as String,
    id: value['entity_id'] as String,
    revision: value['revision'] as int,
    payload: Map<String, Object?>.from(value['payload'] as Map),
    sequence: value['sequence'] as int? ?? 0,
    restored: value['restored'] == true,
  );
}

class PushResult {
  final bool accepted;
  final RemoteEntity entity;
  const PushResult({required this.accepted, required this.entity});
}

class PullPage {
  final List<RemoteEntity> changes;
  final int cursor;
  final bool hasMore;
  const PullPage({
    required this.changes,
    required this.cursor,
    required this.hasMore,
  });
}

abstract interface class SyncTransport {
  bool get configured;
  Future<void> requestOtp(String email);
  Future<AuthSession> verifyOtp(String email, String code);
  Future<AuthSession> refresh(AuthSession session);
  Future<PushResult> push(SyncOperation operation, AuthSession session);
  Future<PullPage> pull(int cursor, AuthSession session);
  void close();
}

class SupabaseSyncClient implements SyncTransport {
  final String url, anonKey;
  final http.Client client;
  SupabaseSyncClient({
    this.url = const String.fromEnvironment('SUPABASE_URL'),
    this.anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
    http.Client? client,
  }) : client = client ?? http.Client();
  @override
  bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
  Future<dynamic> _post(
    String path,
    Map<String, Object?> body, {
    AuthSession? session,
  }) async {
    if (!configured) throw const SyncFailure('unconfigured');
    try {
      final response = await client
          .post(
            Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/$path'),
            headers: {
              'apikey': anonKey,
              'Content-Type': 'application/json',
              if (session != null)
                'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) throw const SyncFailure('auth_required');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const SyncFailure('network');
      }
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const SyncFailure('network');
    }
  }

  @override
  Future<void> requestOtp(String email) async {
    await _post('auth/v1/otp', {'email': email.trim(), 'create_user': true});
  }

  @override
  Future<AuthSession> verifyOtp(String email, String code) async {
    try {
      return AuthSession.fromAuthResponse(
        Map<String, dynamic>.from(
          await _post('auth/v1/verify', {
            'email': email.trim(),
            'token': code.trim(),
            'type': 'email',
          }) as Map,
        ),
      );
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const SyncFailure('auth_required');
    }
  }

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    try {
      return AuthSession.fromAuthResponse(
        Map<String, dynamic>.from(
          await _post('auth/v1/token?grant_type=refresh_token', {
            'refresh_token': session.refreshToken,
          }) as Map,
        ),
      );
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const SyncFailure('auth_required');
    }
  }

  @override
  Future<PushResult> push(SyncOperation operation, AuthSession session) async {
    final result = await _post('rest/v1/rpc/apply_v1_operation', {
      'p_operation': operation.toJson(),
    }, session: session) as Map;
    return PushResult(
      accepted: result['accepted'] == true,
      entity: RemoteEntity.fromJson(result['entity'] as Map),
    );
  }

  @override
  Future<PullPage> pull(int cursor, AuthSession session) async {
    final result = await _post('rest/v1/rpc/pull_v1_changes', {
      'p_after_seq': cursor,
      'p_limit': 100,
    }, session: session) as Map;
    return PullPage(
      changes: (result['changes'] as List)
          .map((value) => RemoteEntity.fromJson(value as Map))
          .toList(),
      cursor: result['cursor'] as int,
      hasMore: result['has_more'] == true,
    );
  }

  @override
  void close() => client.close();
}
