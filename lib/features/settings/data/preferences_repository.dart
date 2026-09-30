import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/settings/app_preferences.dart';

class PreferencesRepository {
  static const String _defaultId = 'default';

  final AppDatabase _db;

  PreferencesRepository(this._db);

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

  Future<void> save(AppPreferences preferences) async {
    await _db.into(_db.preferences).insertOnConflictUpdate(
          PreferencesCompanion(
            id: const Value(_defaultId),
            nickname: Value(preferences.nickname),
            importanceThreshold: Value(preferences.importanceThreshold),
            urgencyThreshold: Value(preferences.urgencyThreshold),
          ),
        );
  }
}
