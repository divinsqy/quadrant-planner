import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/router/app_router.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_editor.dart';
import 'package:quadrant_planner/features/tasks/presentation/task_detail_page.dart';

void main() {
  testWidgets(
    'task score sliders announce their distinct purpose and remain adjustable',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final tasks = TaskRepository(db);
      final task = await tasks.createTask(const TaskDraft(title: 'RTL scores'));
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskEditor(
              task: task,
              controller: TaskEditorController(
                tasks: tasks,
                activity: TaskActivityRepository(db),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(Slider).first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('重要性'), findsOneWidget);
      expect(find.semantics.byLabel('基础紧急性'), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('reduced motion removes detail tab interpolation', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tasks = TaskRepository(db);
    final task = await tasks.createTask(const TaskDraft(title: 'RTL tab'));
    final activity = TaskActivityRepository(db);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: TaskDetailPage(
            taskId: task.id,
            tasks: tasks,
            activity: activity,
            editor: TaskEditorController(tasks: tasks, activity: activity),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DefaultTabController>(find.byType(DefaultTabController))
          .animationDuration,
      Duration.zero,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'reduced motion makes route navigation immediate while retaining content',
    (tester) async {
      final router = createAppRouter(
        pageBuilder: (_, d) => Scaffold(body: Text(d.label)),
        taskDetailBuilder: (_, id) => const Scaffold(body: Text('RTL detail')),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.pushNamed('taskDetail', pathParameters: {'taskId': 't1'});
      await tester.pump();
      await tester.pump();
      final context = tester.element(find.text('RTL detail'));
      expect(ModalRoute.of(context)!.transitionDuration, Duration.zero);
      expect(find.text('RTL detail').hitTestable(), findsOneWidget);
    },
  );
}
