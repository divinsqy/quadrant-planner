import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/backup/backup_service.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late BackupService backups;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('qpb-backup-test-');
    backups = BackupService(db, snapshotDirectory: dir);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'round trip includes settings, evidence and styles, with no session data',
    () async {
      final task = await TaskRepository(db)
          .createTask(const TaskDraft(title: 'dmac_intr RTL 中文'));
      await db
          .into(db.preferences)
          .insert(
            PreferencesCompanion.insert(
              id: 'default',
              nickname: const Value('姓名'),
            ),
          );
      await db
          .into(db.reportStyleProfiles)
          .insert(
            ReportStyleProfilesCompanion.insert(
              id: 'style',
              name: 'technical',
              profileJson: '{}',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      final file = File('${dir.path}/original.qpb');
      await backups.createBackup(file.path);
      expect((await backups.inspectBackup(file.path)).counts['tasks'], 1);
      await db.customUpdate(
        "UPDATE tasks SET title='changed'",
        updates: {db.tasks},
      );
      final snapshot = await backups.restoreBackup(file.path);
      expect(await File(snapshot).exists(), isTrue);
      expect(
        (await TaskRepository(db).get(task.id))!.title,
        'dmac_intr RTL 中文',
      );
      expect(await db.select(db.activityEvents).get(), hasLength(1));
      expect((await db.select(db.preferences).getSingle()).nickname, '姓名');
      expect(await db.select(db.reportStyleProfiles).get(), hasLength(1));
      expect(
        jsonEncode(await backups.exportData()),
        isNot(contains('access_token')),
      );
      expect(
        jsonEncode(await backups.exportData()),
        isNot(contains('sync_profile')),
      );
    },
  );
  test('corrupt backup preserves current data and snapshot', () async {
    await TaskRepository(db).createTask(const TaskDraft(title: 'keep'));
    final corrupt = File('${dir.path}/bad.qpb');
    await corrupt.writeAsBytes([1, 2, 3]);
    await expectLater(
      backups.restoreBackup(corrupt.path),
      throwsA(isA<BackupFailure>()),
    );
    expect((await TaskRepository(db).getTasks()).single.title, 'keep');
    final snapshots = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('pre-restore'))
        .toList();
    expect(snapshots, hasLength(1));
    expect(
      (await backups.inspectBackup(snapshots.single.path)).counts['tasks'],
      1,
    );
  });
  test(
    'hash mismatch, newer schema and bad references roll back after snapshot',
    () async {
      final task = await TaskRepository(db)
          .createTask(const TaskDraft(title: 'current'));
      final original = ZipDecoder().decodeBytes(await backups.bytes());
      final manifest = jsonDecode(
        utf8.decode(original.find('manifest.json')!.readBytes()!),
      ) as Map;
      final data = jsonDecode(
        utf8.decode(original.find('user-data.json')!.readBytes()!),
      ) as Map;
      Future<void> reject(
        Map changedManifest,
        Map changedData,
        String name,
      ) async {
        final manifestBytes = utf8.encode(jsonEncode(changedManifest));
        final dataBytes = utf8.encode(jsonEncode(changedData));
        final archive = Archive()
          ..add(
            ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
          )
          ..add(ArchiveFile('user-data.json', dataBytes.length, dataBytes));
        final path = '${dir.path}/$name.qpb';
        await File(path).writeAsBytes(ZipEncoder().encode(archive));
        await expectLater(
          backups.restoreBackup(path),
          throwsA(isA<BackupFailure>()),
        );
        expect((await TaskRepository(db).get(task.id))!.title, 'current');
      }

      final changed = jsonDecode(jsonEncode(data)) as Map;
      (changed['tables']['tasks'] as List).single['title'] = 'corrupt';
      await reject(manifest, changed, 'hash');
      await reject({...manifest, 'schema_version': 99}, data, 'schema');
      final broken = jsonDecode(jsonEncode(data)) as Map;
      (broken['tables']['tasks'] as List).single['project_id'] = 'missing';
      await reject(
        {
          ...manifest,
          'data_sha256': crypto.sha256
              .convert(utf8.encode(jsonEncode(broken)))
              .toString(),
        },
        broken,
        'references',
      );
      expect(
        dir.listSync().whereType<File>().where(
          (f) => f.path.contains('pre-restore'),
        ),
        hasLength(3),
      );
    },
  );
  test(
    'backup includes all project, planner, focus and immutable history rows',
    () async {
      final at = DateTime.utc(2026, 10, 3);
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p',
              name: 'DMAC',
              createdAt: at,
              updatedAt: at,
            ),
          );
      await db
          .into(db.milestones)
          .insert(
            MilestonesCompanion.insert(
              id: 'm',
              projectId: 'p',
              name: 'RTL',
              createdAt: at,
              updatedAt: at,
            ),
          );
      await db
          .into(db.milestoneHistory)
          .insert(
            MilestoneHistoryCompanion.insert(
              milestoneId: 'm',
              projectId: 'p',
              name: 'RTL',
              createdAt: at,
              occurredAt: at,
            ),
          );
      final tasks = TaskRepository(db);
      final task = await tasks.createTask(
        const TaskDraft(title: 'UVM', projectId: 'p', milestoneId: 'm'),
      );
      final prerequisite = await tasks.createTask(
        const TaskDraft(title: 'AXI'),
      );
      await db
          .into(db.subtasks)
          .insert(
            SubtasksCompanion.insert(
              id: 's',
              taskId: task.id,
              title: 'test',
              createdAt: at,
              updatedAt: at,
            ),
          );
      await db
          .into(db.dependencies)
          .insert(
            DependenciesCompanion.insert(
              id: 'd',
              taskId: task.id,
              dependsOnTaskId: prerequisite.id,
              createdAt: at,
            ),
          );
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: 'tag', name: 'RTL'));
      await db
          .into(db.taskTags)
          .insert(TaskTagsCompanion.insert(taskId: task.id, tagId: 'tag'));
      await db
          .into(db.workScheduleWindows)
          .insert(
            WorkScheduleWindowsCompanion.insert(
              id: 'w',
              weekday: 1,
              startMinutes: 540,
              endMinutes: 720,
            ),
          );
      await db
          .into(db.weekendOverrides)
          .insert(
            WeekendOverridesCompanion.insert(
              id: 'o',
              localDate: '2026-10-10',
              startMinutes: 840,
              endMinutes: 900,
            ),
          );
      await db
          .into(db.dailyPlanBlocks)
          .insert(
            DailyPlanBlocksCompanion.insert(
              id: 'b',
              localDate: '2026-10-05',
              taskId: task.id,
              startMinutes: 540,
              endMinutes: 600,
              isLocked: const Value(true),
            ),
          );
      await db
          .into(db.plannerTaskOverrides)
          .insert(
            PlannerTaskOverridesCompanion.insert(
              localDate: '2026-10-05',
              taskId: task.id,
              action: 'pin',
            ),
          );
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              id: 'f',
              taskId: task.id,
              state: 'completed',
              startedAt: at,
              endedAt: Value(at.add(const Duration(minutes: 20))),
              planBlockId: const Value('b'),
            ),
          );
      await db
          .into(db.weeklyReports)
          .insert(
            WeeklyReportsCompanion.insert(
              id: 'r',
              fromDate: '2026-09-28',
              toDate: '2026-10-04',
              contentJson: '{}',
              createdAt: at,
              updatedAt: at,
            ),
          );
      await db
          .into(db.weeklyNotes)
          .insert(
            WeeklyNotesCompanion.insert(
              id: 'n',
              weekStart: '2026-09-28',
              taskId: Value(task.id),
              problem: const Value('RTL'),
              createdAt: at,
            ),
          );
      final expected = await backups.exportData();
      final file = '${dir.path}/full.qpb';
      await backups.createBackup(file);
      await db.customUpdate(
        "UPDATE tasks SET title='mutated'",
        updates: {db.tasks},
      );
      await backups.restoreBackup(file);
      expect(await backups.exportData(), expected);
    },
  );
}
