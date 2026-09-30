import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'store.dart';

class CloudConfig {
  final String url;
  final String anonKey;
  const CloudConfig(this.url, this.anonKey);

  factory CloudConfig.fromEnvironment() => const CloudConfig(
        String.fromEnvironment('SUPABASE_URL'),
        String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

  bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
}

class SyncClient {
  final LocalStore store;
  final CloudConfig config;
  final http.Client _http;
  final FlutterSecureStorage _secure;

  SyncClient(
    this.store, {
    CloudConfig? config,
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  })  : config = config ?? CloudConfig.fromEnvironment(),
        _http = httpClient ?? http.Client(),
        _secure = secureStorage ?? const FlutterSecureStorage();

  Future<Map<String, String>?> _session() async {
    final uid = await _secure.read(key: 'quadrant.uid');
    final token = await _secure.read(key: 'quadrant.access_token');
    if (uid == null || token == null) return null;
    return {'uid': uid, 'token': token};
  }

  Future<void> requestOtp(String email) async {
    _requireConfigured();
    await _request(
      '/auth/v1/otp',
      body: {'email': email.trim(), 'create_user': true},
      authenticated: false,
    );
  }

  Future<String> verifyOtp(String email, String token) async {
    _requireConfigured();
    final response = await _request(
      '/auth/v1/verify',
      body: {'email': email.trim(), 'token': token.trim(), 'type': 'email'},
      authenticated: false,
    );
    final map = _asMap(response);
    final user = _asMap(map['user']);
    final uid = user['id']?.toString();
    final access = map['access_token']?.toString();
    if (uid == null || access == null) throw StateError('AUTH_RESPONSE_INVALID');

    await _secure.write(key: 'quadrant.uid', value: uid);
    await _secure.write(key: 'quadrant.access_token', value: access);
    await store.createAccountProfile(uid);
    return uid;
  }

  Future<void> syncNow() async {
    _requireConfigured();
    final session = await _session();
    if (session == null) throw StateError('AUTH_REQUIRED');

    final profile = await store.activeProfile();
    if (profile['kind'] != 'account' || profile['sync_enabled'] != 1) return;

    await store.setCursorAndStatus(await store.cursor(), 'syncing');

    final pending = await store.pendingOutbox();
    for (final row in pending) {
      final batchId = row['batch_id'] as String;
      final payload =
          (jsonDecode(row['payload_json'] as String) as Map).cast<String, Object?>();
      try {
        final response = await _request(
          '/rest/v1/rpc/apply_entity_batch',
          body: {'p_batch': payload},
        );
        final result = _unwrapRpcObject(response);
        final ok = result['ok'] == true;
        if (!ok) {
          final error = result['error'] is Map
              ? (result['error'] as Map).cast<String, Object?>()
              : <String, Object?>{};
          final code = error['code']?.toString() ?? 'SYNC_FAILED';
          if (code == 'REVISION_CONFLICT') {
            await store.markOutboxStatus(batchId, 'conflict');
            await store.addConflict(
              entityId: payload['entity_id']?.toString() ?? 'unknown',
              cloud: error['cloud'],
              local: payload,
            );
          } else {
            await store.markOutboxStatus(batchId, 'failed');
          }
          continue;
        }

        final revision = (result['revision'] as num?)?.toInt() ??
            int.tryParse(result['revision']?.toString() ?? '') ??
            0;
        await store.markBatchApplied(
          batchId: batchId,
          entityId: payload['entity_id']?.toString() ?? '',
          revision: revision,
        );
      } catch (_) {
        await store.markOutboxStatus(batchId, 'failed');
        rethrow;
      }
    }

    while (true) {
      final after = await store.cursor();
      final response = await _request(
        '/rest/v1/rpc/pull_changes',
        body: {'p_after_seq': after, 'p_limit': 100},
      );
      final result = _unwrapRpcObject(response);
      if (result['ok'] != true) throw StateError('PULL_FAILED');

      final changes = result['changes'] is List
          ? (result['changes'] as List).cast<Object?>()
          : <Object?>[];
      final nextCursor = (result['next_cursor'] as num?)?.toInt() ??
          int.tryParse(result['next_cursor']?.toString() ?? '') ??
          after;
      final head = (result['head_seq'] as num?)?.toInt() ??
          int.tryParse(result['head_seq']?.toString() ?? '') ??
          nextCursor;

      await store.applyRemotePage(changes, nextCursor);
      if (nextCursor >= head || changes.isEmpty) break;
    }

    await store.setCursorAndStatus(await store.cursor(), 'idle');
  }

  Future<void> disableSync() => store.disableSync();

  Future<void> logout() async {
    await store.disableSync();
    await _secure.delete(key: 'quadrant.uid');
    await _secure.delete(key: 'quadrant.access_token');
    await store.switchToLocalProfile();
  }

  Future<Object?> _request(
    String path, {
    required Map<String, Object?> body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('${config.url}$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'apikey': config.anonKey,
    };
    if (authenticated) {
      final session = await _session();
      if (session == null) throw StateError('AUTH_REQUIRED');
      headers['Authorization'] = 'Bearer ${session['token']}';
    }

    final response = await _http.post(uri, headers: headers, body: jsonEncode(body));
    final Object? decoded =
        response.body.trim().isEmpty ? <String, Object?>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded['message'] ?? decoded['error'] : decoded;
      throw StateError('HTTP ${response.statusCode}: $error');
    }
    return decoded;
  }

  Map<String, Object?> _unwrapRpcObject(Object? value) {
    if (value is List && value.isNotEmpty) return _asMap(value.first);
    return _asMap(value);
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    throw StateError('EXPECTED_JSON_OBJECT');
  }

  void _requireConfigured() {
    if (!config.configured) throw StateError('CLOUD_NOT_CONFIGURED');
  }

  void dispose() => _http.close();
}
