import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quadrant_planner/core/sync/secure_session_store.dart';
import 'package:quadrant_planner/core/sync/supabase_sync_client.dart';
import 'package:quadrant_planner/core/sync/sync_operation.dart';

void main() {
  test('OTP, refresh, operation and paginated pull match REST boundary; errors are redacted', () async {
    final requests = <http.Request>[];
    final client = SupabaseSyncClient(
      url: 'https://example.supabase.co',
      anonKey: 'public-key',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/verify') ||
            request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'user': {'id': 'u'},
              'access_token': 'ACCESS_FIXTURE',
              'refresh_token': 'REFRESH_FIXTURE',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/apply_v1_operation')) {
          return http.Response(
            jsonEncode({
              'accepted': true,
              'entity': {
                'entity_kind': 'preferences',
                'entity_id': 'default',
                'revision': 1,
                'payload': {'id': 'default', 'nickname': 'RTL'},
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/pull_v1_changes')) {
          return http.Response(
            jsonEncode({'changes': [], 'cursor': 42, 'has_more': false}),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    await client.requestOtp('a@example.com');
    final session = await client.verifyOtp('a@example.com', '123456');
    expect(session.toString(), isNot(contains('FIXTURE')));
    await client.refresh(session);
    expect(requests.last.url.queryParameters['grant_type'], 'refresh_token');
    final op = SyncOperation(
      operationId: 'same-id',
      entityKind: 'preferences',
      entityId: 'default',
      baseRevision: 0,
      changedFields: {'nickname'},
      payload: {'id': 'default', 'nickname': 'RTL'},
    );
    expect((await client.push(op, session)).accepted, isTrue);
    expect(
      (jsonDecode(requests.last.body) as Map)['p_operation']['operation_id'],
      'same-id',
    );
    expect(requests.last.headers['Authorization'], startsWith('Bearer '));
    expect((await client.pull(40, session)).cursor, 42);
    final failed = SupabaseSyncClient(
      url: 'https://example.supabase.co',
      anonKey: 'public',
      client: MockClient(
        (_) async => http.Response('ACCESS_FIXTURE REFRESH_FIXTURE', 500),
      ),
    );
    addTearDown(failed.close);
    try {
      await failed.requestOtp('a');
      fail('must reject');
    } catch (error) {
      expect(error.toString(), 'SyncFailure(network)');
    }
  });
  test('macOS sessions use OS keychain without a provisioning-only sharing capability', () {
    const store = OsSecureSessionStore();
    expect(
      store.storage.mOptions.toMap()['usesDataProtectionKeychain'],
      'false',
    );
  });
  test(
    'secure session storage alone receives token values and can clear them',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = OsSecureSessionStore();
      final session = AuthSession(
        userId: 'u',
        accessToken: 'private-access',
        refreshToken: 'private-refresh',
        expiresAt: DateTime.utc(2100),
      );
      await store.write(session);
      expect((await store.read())!.userId, 'u');
      await store.clear();
      expect(await store.read(), isNull);
    },
  );
}
