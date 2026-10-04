import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/dashboard/application/dashboard_controller.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/tags/data/tag_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  test(
    'quadrant metadata includes project tags and remaining workdays',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final projects = ProjectRepository(db);
      final project = await projects.createProject(
        name: 'Release',
        objective: 'Ship',
      );
      final tasks = TaskRepository(db);
      final task = await tasks.createTask(
        TaskDraft(
          title: 'Metadata task',
          projectId: project.id,
          status: TaskStatus.planned,
          deadline: DateTime(2026, 10, 5),
        ),
      );
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: 'rtl', name: 'RTL'));
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: 'uvm', name: 'UVM'));
      for (final tag in ['rtl', 'uvm']) {
        await db
            .into(db.taskTags)
            .insert(TaskTagsCompanion.insert(taskId: task.id, tagId: tag));
      }
      final tags = TagRepository(db);
      final controller = DashboardController(
        tasks: tasks,
        preferences: PreferencesRepository(db),
        projects: projects,
        tags: tags,
        calendar: WorkCalendar(
          schedule: WorkSchedule.standard(),
          coveredYears: const {2026},
          holidays: const {},
        ),
        clock: () => DateTime(2026, 9, 30, 9),
      );
      addTearDown(() async {
        controller.dispose();
        await db.close();
      });
      controller.start();
      await tags.watchTaskTags().first;
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.taskMetadata[task.id]?['项目'], 'Release');
      expect(controller.state.taskMetadata[task.id]?['标签'], 'RTL、UVM');
      expect(controller.state.taskMetadata[task.id]?['剩余工作日'], '3');
    },
  );
}
