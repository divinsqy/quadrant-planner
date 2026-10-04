import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/core/sync/sync_coordinator.dart';
import 'package:quadrant_planner/features/settings/presentation/sync_center.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

import '../../support/sync_fakes.dart' show FakeCloud, MemorySessions;

void main() {
  testWidgets(
    'Sync Center reports offline pending count and retries without exposing tokens',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cloud = FakeCloud()..fail = true;
      final sync = SyncCoordinator(
        db: db,
        sessions: MemorySessions(),
        transport: cloud,
      );
      addTearDown(sync.dispose);
      await sync.signIn('a', '1');
      await TaskRepository(db).createTask(const TaskDraft(title: 'RTL'));
      await sync.syncOnce();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SyncCenter(coordinator: sync)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('待同步'), findsWidgets);
      expect(find.textContaining('SECRET'), findsNothing);
      cloud.fail = false;
      await tester.tap(find.text('立即同步'));
      await tester.pumpAndSettle();
      expect(find.text('已同步'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
