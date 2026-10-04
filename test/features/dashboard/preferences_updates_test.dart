import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';

void main() {
  test('nickname and threshold updates preserve each other', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final preferences = PreferencesRepository(db);
    await Future.wait([
      preferences.updateNickname('Divins'),
      preferences.updateThresholds(importance: 62, urgency: 57),
    ]);
    final saved = await preferences.watch().first;
    expect(saved.nickname, 'Divins');
    expect(saved.importanceThreshold, 62);
    expect(saved.urgencyThreshold, 57);
  });
}
