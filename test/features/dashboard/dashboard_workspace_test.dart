import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/projects/project.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/dashboard/application/dashboard_controller.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  test(
    'Now waits for the initial dependency query before recommending',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final tasks = TaskRepository(db);
      final blocked = StreamController<Set<String>>();
      await tasks.createTask(
        const TaskDraft(
          title: 'Await dependency facts',
          status: TaskStatus.planned,
        ),
      );
      final controller = DashboardController(
        tasks: tasks,
        preferences: PreferencesRepository(db),
        blockedTaskIds: blocked.stream,
        calendar: WorkCalendar(
          schedule: WorkSchedule.standard(),
          coveredYears: const {2026},
          holidays: const {},
        ),
      );
      addTearDown(() async {
        controller.dispose();
        await blocked.close();
        await db.close();
      });
      controller.start();
      await tasks.watchExecutableTasks().first;
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.currentRecommendation, isNull);
      blocked.add({});
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.currentRecommendation, isNotNull);
    },
  );
  for (final holiday in [false, true]) {
    test(
      holiday
          ? 'holiday queue uses effective calendar windows'
          : 'Now slot fit uses remaining time in the current window',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final tasks = TaskRepository(db);
        await tasks.createTask(
          const TaskDraft(
            title: 'One hour',
            status: TaskStatus.planned,
            estimatedMinutes: 60,
          ),
        );
        final controller = DashboardController(
          tasks: tasks,
          preferences: PreferencesRepository(db),
          calendar: WorkCalendar(
            schedule: WorkSchedule.standard(),
            coveredYears: const {2026},
            holidays: holiday ? const {'2026-10-02'} : const {},
          ),
          clock: () => DateTime(2026, 10, 2, 11, 45),
        );
        addTearDown(() async {
          controller.dispose();
          await db.close();
        });
        controller.start();
        await tasks.watchExecutableTasks().first;
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.snapshots.single.fitsCurrentSlot, isFalse);
        if (holiday) expect(controller.state.todayPlan.blocks, isEmpty);
      },
    );
  }
  test(
    'project filter and selection persist while dependencies update Now',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final blocked = StreamController<Set<String>>();
      var id = 0;
      final tasks = TaskRepository(db, idFactory: () => 'task-${++id}');
      final now = DateTime(2026, 9, 30, 10);
      await ProjectRepository(db).save(
        Project(
          id: 'p1',
          name: 'Project one',
          objective: '',
          deadline: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final first = await tasks.createTask(
        const TaskDraft(
          title: 'First',
          projectId: 'p1',
          status: TaskStatus.planned,
          importance: 90,
          baseUrgency: 90,
          estimatedMinutes: 30,
        ),
      );
      final second = await tasks.createTask(
        const TaskDraft(
          title: 'Second',
          status: TaskStatus.planned,
          estimatedMinutes: 30,
        ),
      );
      final controller = DashboardController(
        tasks: tasks,
        preferences: PreferencesRepository(db),
        calendar: WorkCalendar(
          schedule: WorkSchedule.standard(),
          coveredYears: const {2026},
          holidays: const {},
        ),
        blockedTaskIds: blocked.stream,
        clock: () => now,
      );
      addTearDown(() async {
        controller.dispose();
        await blocked.close();
        await db.close();
      });
      controller.start();
      await controller.tasks.watchExecutableTasks().first;
      await Future<void>.delayed(Duration.zero);
      controller.selectTask(first.id);
      controller.filterProject('p1');
      expect(controller.state.snapshots.map((s) => s.task.id), [first.id]);
      expect(controller.state.selectedTaskId, first.id);
      expect(controller.state.projectId, 'p1');
      blocked.add({first.id});
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.snapshots.single.dependenciesSatisfied, isFalse);
      expect(controller.state.currentRecommendation, isNull);
      expect((await tasks.get(first.id))!.projectId, 'p1');
      controller.filterProject(null);
      expect(controller.state.currentRecommendation!.task.id, second.id);
      expect(controller.state.selectedTaskId, first.id);
      controller.setListExpanded(false);
      expect(controller.state.listExpanded, isFalse);
    },
  );
}
