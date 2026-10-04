import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthSession {
  final String userId, accessToken, refreshToken;
  final DateTime expiresAt;
  const AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });
  @override
  String toString() => 'AuthSession(redacted)';
  Map<String, Object?> _encode() => {
    'user_id': userId,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
  factory AuthSession.fromAuthResponse(Map<String, dynamic> value) =>
      AuthSession(
        userId: (value['user'] as Map)['id'] as String,
        accessToken: value['access_token'] as String,
        refreshToken: value['refresh_token'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (value['expires_at'] as int? ??
                  (DateTime.now().millisecondsSinceEpoch ~/ 1000) +
                      (value['expires_in'] as int? ?? 3600)) *
              1000,
          isUtc: true,
        ),
      );
}

abstract interface class SecureSessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

class OsSecureSessionStore implements SecureSessionStore {
  final FlutterSecureStorage storage;
  static const _key = 'quadrant.v1.session';
  // This app does not share credentials with other apps. The macOS standard
  // Keychain works with ad-hoc signing without a provisioning profile.
  const OsSecureSessionStore({
    this.storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  });
  @override
  Future<AuthSession?> read() async {
    final text = await storage.read(key: _key);
    if (text == null) return null;
    try {
      final value = jsonDecode(text) as Map;
      return AuthSession(
        userId: value['user_id'] as String,
        accessToken: value['access_token'] as String,
        refreshToken: value['refresh_token'] as String,
        expiresAt: DateTime.parse(value['expires_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) =>
      storage.write(key: _key, value: jsonEncode(session._encode()));
  @override
  Future<void> clear() => storage.delete(key: _key);
}
