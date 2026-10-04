import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/sync/conflict_repository.dart';
import 'package:quadrant_planner/core/sync/field_merge.dart';
import 'package:quadrant_planner/core/sync/outbox_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/settings/presentation/sync_conflicts_page.dart';

void main() {
  testWidgets(
    'long text can retain either version or save an explicit merged text',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await OutboxRepository(db).activate('u');
      final task = await TaskRepository(db)
          .createTask(const TaskDraft(title: 'AXI', description: 'local'));
      final conflicts = ConflictRepository(db);
      await conflicts.record(
        'tasks',
        task.id,
        const FieldConflict('description', 'base', 'local', 'remote'),
      );
      await tester.pumpWidget(
        MaterialApp(home: SyncConflictsPage(repository: conflicts)),
      );
      await tester.pumpAndSettle();
      expect(find.text('保留本地'), findsOneWidget);
      expect(find.text('保留远端'), findsOneWidget);
      await db.customUpdate(
        'UPDATE tasks SET description=? WHERE id=?',
        variables: [const Variable('新本地更新 RTL'), Variable(task.id)],
        updates: {db.tasks},
      );
      await tester.pumpAndSettle();
      expect(find.text('本地：新本地更新 RTL'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'RTL 与 UVM 合并记录');
      await tester.tap(find.text('保存合并文本'));
      await tester.pumpAndSettle();
      expect(await conflicts.unresolved(), isEmpty);
      expect(
        (await TaskRepository(db).get(task.id))!.description,
        'RTL 与 UVM 合并记录',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
