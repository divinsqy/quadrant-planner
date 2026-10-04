import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/settings/app_preferences.dart';

class PreferencesRepository {
  static const String _defaultId = 'default';

  final AppDatabase _db;

  PreferencesRepository(this._db);

  Future<void> updateNickname(String nickname) =>
      _update(PreferencesCompanion(nickname: Value(nickname.trim())));

  Future<void> updateThresholds({
    required int importance,
    required int urgency,
  }) => _update(
    PreferencesCompanion(
      importanceThreshold: Value(importance.clamp(0, 100)),
      urgencyThreshold: Value(urgency.clamp(0, 100)),
    ),
  );

  Future<void> _update(PreferencesCompanion changes) =>
      _db.transaction(() async {
        await _db
            .into(_db.preferences)
            .insert(
              PreferencesCompanion.insert(id: _defaultId),
              mode: InsertMode.insertOrIgnore,
            );
        await (_db.update(
          _db.preferences,
        )..where((row) => row.id.equals(_defaultId))).write(changes);
      });

  Stream<AppPreferences> watch() {
    final query = _db.select(_db.preferences)
      ..where((row) => row.id.equals(_defaultId));
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? AppPreferences.defaults()
          : AppPreferences(
              nickname: row.nickname,
              importanceThreshold: row.importanceThreshold,
              urgencyThreshold: row.urgencyThreshold,
            ),
    );
  }

  Future<AppPreferences> get() async {
    final row = await (_db.select(
      _db.preferences,
    )..where((r) => r.id.equals(_defaultId))).getSingleOrNull();
    return row == null
        ? AppPreferences.defaults()
        : AppPreferences(
            nickname: row.nickname,
            importanceThreshold: row.importanceThreshold,
            urgencyThreshold: row.urgencyThreshold,
          );
  }

  Future<void> save(AppPreferences preferences) async {
    await _db
        .into(_db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion(
            id: const Value(_defaultId),
            nickname: Value(preferences.nickname),
            importanceThreshold: Value(preferences.importanceThreshold),
            urgencyThreshold: Value(preferences.urgencyThreshold),
          ),
        );
  }
}
