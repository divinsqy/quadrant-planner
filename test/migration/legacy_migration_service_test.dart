import '../support/legacy_fixture.dart';

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/migration/legacy_migration_service.dart';
import 'package:quadrant_planner/migration/legacy_models.dart';

void main() {
  late Directory tempDir;
  late String legacyPath;
  late AppDatabase database;

  setUp(() async {
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('quadrant-legacy-test-');
    legacyPath = '${tempDir.path}/quadrant.sqlite';
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await createLegacyFixture(legacyPath);
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'preview reports valid rows and malformed rows without changing source',
    () async {
      final before = await File(legacyPath).readAsBytes();
      final service = LegacyMigrationService(
        database: database,
        legacyDatabasePath: legacyPath,
        calendarProvider: (_) async =>
            const LegacyCalendar(coveredYears: {2026}, holidays: {}),
      );

      final preview = await service.preview();

      expect(preview.taskCount, 3);
      expect(preview.tagCount, 2);
      expect(preview.eventCount, 2);
      expect(preview.skipped.length, 1);
      expect(preview.skipped.single.entityKind, 'task');
      expect(await File(legacyPath).readAsBytes(), before);
    },
  );

  test('migrate normalizes scores, maps statuses, imports links, and is idempotent', () async {
    final before = await File(legacyPath).readAsBytes();
    final service = LegacyMigrationService(
      database: database,
      legacyDatabasePath: legacyPath,
      calendarProvider: (_) async =>
          const LegacyCalendar(coveredYears: {2026}, holidays: {}),
    );

    final result = await service.migrate(
      migrationAt: DateTime.utc(2026, 9, 30, 9),
    );

    expect(result.alreadyMigrated, isFalse);
    expect(result.importedTasks, 3);
    expect(result.importedTags, 2);
    expect(result.importedEvents, 2);
    expect(result.skipped.length, 1);
    expect(result.sourceHash, isNotEmpty);

    final tasks = await database.select(database.tasks).get();
    final byId = {for (final task in tasks) task.id: task};

    expect(byId['t-active']!.status, TaskStatus.planned.name);
    expect(byId['t-active']!.importance, 50);
    // Legacy urgency is 0 on 9/28 and gains two workdays by 9/30:
    // 2 in old range -15..5 maps to 85 in v1.
    expect(byId['t-active']!.baseUrgency, 85);
    expect(
      byId['t-active']!.baseUrgencyAnchorAt.toUtc(),
      DateTime.utc(2026, 9, 30, 9),
    );

    expect(byId['t-completed']!.status, TaskStatus.completed.name);
    expect(byId['t-deleted']!.status, TaskStatus.cancelled.name);
    expect(byId['t-deleted']!.deletedAt, isNotNull);

    final links = await database.select(database.taskTags).get();
    expect(
      links.map((row) => '${row.taskId}:${row.tagId}').toSet(),
      containsAll({'t-active:tag-dma', 't-active:tag-rtl'}),
    );

    final second = await service.migrate(
      migrationAt: DateTime.utc(2026, 9, 30, 10),
    );
    expect(second.alreadyMigrated, isTrue);
    expect(second.importedTasks, 0);
    expect((await database.select(database.tasks).get()).length, 3);
    expect(await File(legacyPath).readAsBytes(), before);
  });
}
