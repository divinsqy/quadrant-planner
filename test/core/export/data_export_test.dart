import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/export/json_data_exporter.dart';
import 'package:quadrant_planner/core/export/csv_task_exporter.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  test('portable JSON and CSV preserve technical Chinese text and explicit deletion', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p',
            name: 'RTL',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final task = await TaskRepository(db).createTask(
      const TaskDraft(title: 'dmac_regfile, "AXI"\n验证', projectId: 'p'),
    );
    await db.into(db.tags).insert(TagsCompanion.insert(id: 'tag', name: 'UVM'));
    await db
        .into(db.taskTags)
        .insert(TaskTagsCompanion.insert(taskId: task.id, tagId: 'tag'));
    await TaskRepository(db).softDelete(task.id, now);
    final data = jsonDecode(await JsonDataExporter(db).render()) as Map;
    expect(data['schema_version'], 5);
    final tables = data['tables'] as Map;
    expect(tables['projects'], hasLength(1));
    expect(tables['tags'], hasLength(1));
    expect((tables['tasks'] as List).single['deleted_at'], isNotNull);
    expect(jsonEncode(data), isNot(contains('refresh_token')));
    final csv = await CsvTaskExporter(db).render();
    expect(csv, contains('"dmac_regfile, ""AXI""\n验证"'));
    expect(csv, contains('UVM'));
    expect(csv, contains('deleted_at'));
    expect(
      await CsvTaskExporter(db).render(includeDeleted: false),
      isNot(contains('dmac_regfile')),
    );
  });
}
