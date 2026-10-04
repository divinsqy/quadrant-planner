import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/reports/report_style_profile.dart';
import 'package:quadrant_planner/domain/reports/weekly_report.dart';
import 'package:quadrant_planner/domain/settings/app_preferences.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/projects/milestone.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/focus/data/focus_repository.dart';
import 'package:quadrant_planner/features/reports/application/weekly_report_builder.dart';
import 'package:quadrant_planner/features/reports/data/report_repository.dart';
import 'package:quadrant_planner/features/reports/data/weekly_note_repository.dart';
import 'package:quadrant_planner/features/settings/data/preferences_repository.dart';
import 'package:quadrant_planner/features/tasks/application/task_editor_controller.dart';
import 'package:quadrant_planner/features/tasks/data/task_activity_repository.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late TaskEditorController editor;
  late ReportRepository reports;
  late WeeklyNoteRepository notes;
  late DateTime now;
  final week = DateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 11));
  Future<WeeklyReport> build() => WeeklyReportBuilder(
    reports: reports,
    clock: () => now,
  ).build(week, ReportStyleProfile.standard());
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime(2026, 10, 6, 9);
    tasks = TaskRepository(db, clock: () => now);
    editor = TaskEditorController(
      tasks: tasks,
      activity: TaskActivityRepository(db),
      clock: () => now,
    );
    reports = ReportRepository(db, clock: () => now);
    notes = WeeklyNoteRepository(db, clock: () => now);
  });
  tearDown(() => db.close());
  test('historical builder refuses later task changes whose old values were not recorded', () async {
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'RTL 早期工作',
        status: TaskStatus.inProgress,
        progress: 60,
      ),
    );
    now = DateTime(2026, 10, 20);
    await tasks.save(
      task.copyWith(title: 'CPU 后来的结果', progress: 95, updatedAt: now),
    );
    expect((await build()).workItems, isEmpty);
  });

  test('completed work deduplicates activity and Focus while preserving technical result and evidence', () async {
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'RTL dmac_regfile AXI 验证',
        status: TaskStatus.planned,
        estimatedMinutes: 60,
      ),
    );
    final focus = FocusRepository(db);
    await focus.start(task.id, now);
    now = now.add(const Duration(minutes: 25));
    await focus.complete(now);
    final partial = await tasks.createTask(
      const TaskDraft(
        title: 'UVM dmac_intr 覆盖率',
        status: TaskStatus.inProgress,
      ),
    );
    await editor.save(partial, progress: 60);
    await notes.add(
      taskId: task.id,
      weekStart: week.start,
      problem: 'AXI 响应乱序',
      cause: 'ID 未关联',
      solution: '补齐 RTL dmac_regfile AXI 验证',
      learning: '保留 transaction ID',
    );
    await tasks.createTask(
      TaskDraft(
        title: '补齐 UVM 回归',
        status: TaskStatus.planned,
        deadline: DateTime(2026, 10, 13),
      ),
    );
    final report = await build();
    expect(report.workItems, hasLength(2));
    final completed = report.workItems.singleWhere((i) => i.progress == 100);
    expect(completed.text, contains('RTL dmac_regfile AXI'));
    expect(
      completed.evidence.map((e) => e.kind),
      containsAll(['task', 'activity', 'focus', 'note']),
    );
    expect(
      report.workItems.singleWhere((i) => i.progress == 60).text,
      'UVM dmac_intr 覆盖率',
    );
    expect(report.reflections.single.question, 'AXI 响应乱序');
    expect(report.reflections.single.answer, contains('ID 未关联'));
    expect(report.reflections.single.answer, contains('transaction ID'));
    expect(report.nextWeekItems.single.text, '补齐 UVM 回归');
    expect(report.supervisorFeedback, isEmpty);
    expect(report.workItems.every((i) => i.evidence.isNotEmpty), isTrue);
  });

  test(
    'titles and metadata edits alone never become accomplishments',
    () async {
      final task = await tasks.createTask(
        const TaskDraft(title: '完成所有 RTL', status: TaskStatus.planned),
      );
      await editor.save(task, importance: 90);
      final report = await build();
      expect(report.workItems, isEmpty);
      expect(report.nextWeekItems, isEmpty);
    },
  );

  test('zero completed tasks still produce progress and Q/A notes', () async {
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'UVM scoreboarding',
        status: TaskStatus.inProgress,
        progress: 60,
      ),
    );
    await notes.add(
      taskId: task.id,
      weekStart: week.start,
      problem: 'AXI timeout',
      solution: '添加 timeout 日志',
    );
    final report = await build();
    expect(report.workItems.single.progress, 60);
    expect(report.reflections.single.answer, contains('添加 timeout 日志'));
  });
  test('completion followed by reopening retains current progress and completion only as evidence', () async {
    final task = await tasks.createTask(
      const TaskDraft(title: 'UVM dmac_intr 回归', status: TaskStatus.inProgress),
    );
    await editor.complete(task);
    now = now.add(const Duration(hours: 1));
    await editor.save(task, status: TaskStatus.inProgress, progress: 60);
    final report = await build();
    expect(report.workItems.single.progress, 60);
    expect(report.workItems.single.evidence.first.detail, 'inProgress · 60%');
    expect(
      report.workItems.single.evidence.any(
        (e) => e.kind == 'activity' && e.detail == '任务完成',
      ),
      isTrue,
    );
  });
  test('historical milestone retains completion result after later name and deadline edits', () async {
    final projects = ProjectRepository(db, clock: () => now);
    final project = await projects.createProject(name: 'DMAC');
    final milestone = await projects.createMilestone(
      projectId: project.id,
      name: 'RTL AXI 交付',
    );
    await projects.saveMilestone(
      Milestone(
        id: milestone.id,
        projectId: project.id,
        name: milestone.name,
        deadline: null,
        completedAt: now,
        createdAt: milestone.createdAt,
        updatedAt: now,
      ),
    );
    now = DateTime(2026, 10, 20);
    await projects.saveMilestone(
      Milestone(
        id: milestone.id,
        projectId: project.id,
        name: '未来 CPU 目标',
        deadline: DateTime(2026, 11, 1),
        completedAt: milestone.createdAt,
        createdAt: milestone.createdAt,
        updatedAt: now,
      ),
    );
    final report = await build();
    expect(report.workItems.single.text, 'RTL AXI 交付');
    expect(report.workItems.single.progress, 100);
    expect(report.workItems.single.evidence.single.kind, 'milestone');
    expect(report.workItems.single.evidence.single.title, 'RTL AXI 交付');
  });

  test('historical builder excludes future progress and reconstructs title at week end', () async {
    final task = await tasks.createTask(
      const TaskDraft(title: 'dmac_intr 验证', status: TaskStatus.inProgress),
    );
    await editor.save(task, progress: 60);
    now = DateTime(2026, 10, 13);
    await editor.save((await tasks.get(task.id))!, progress: 95, title: '全新结果');
    final report = await build();
    expect(report.workItems.single.progress, 60);
    expect(report.workItems.single.text, 'dmac_intr 验证');
    expect(
      report.workItems.single.evidence.any((e) => e.detail.contains('95')),
      isFalse,
    );
  });

  test(
    'metadata edit does not repeat old partial progress as this week result',
    () async {
      now = DateTime(2026, 9, 28);
      final task = await tasks.createTask(
        const TaskDraft(
          title: 'RTL 上周进度',
          status: TaskStatus.inProgress,
          progress: 60,
        ),
      );
      now = DateTime(2026, 10, 7);
      await editor.save(task, importance: 90, title: 'RTL 更新标题');
      expect((await build()).workItems, isEmpty);
    },
  );

  test('historical same timestamp edits roll back in recorded order rather than UUID order', () async {
    final task = await tasks.createTask(
      const TaskDraft(
        title: 'RTL 旧结果',
        status: TaskStatus.inProgress,
        progress: 60,
      ),
    );
    now = DateTime(2026, 10, 13);
    var id = 0;
    final tiedEditor = TaskEditorController(
      tasks: tasks,
      activity: TaskActivityRepository(
        db,
        idFactory: () => ['future-a', 'future-z'][id++],
      ),
      clock: () => now,
    );
    await tiedEditor.save(task, progress: 80, title: 'RTL 中间结果');
    await tiedEditor.save(task, progress: 95, title: 'RTL 新结果');
    final report = await build();
    expect(report.workItems.single.progress, 60);
    expect(report.workItems.single.text, 'RTL 旧结果');
  });

  test(
    'Focus overlapping the week clips timestamps and excludes pause time',
    () async {
      now = DateTime(2026, 10, 4, 23, 40);
      final task = await tasks.createTask(
        const TaskDraft(title: 'AXI 调试', status: TaskStatus.planned),
      );
      final focus = FocusRepository(db);
      await focus.start(task.id, DateTime(2026, 10, 4, 23, 50));
      await focus.pause(DateTime(2026, 10, 5, 0, 10));
      await focus.complete(DateTime(2026, 10, 5, 0, 20), completeTask: false);
      now = DateTime(2026, 10, 11, 23);
      final report = await build();
      expect(report.workItems.single.text, contains('本周专注 10 分钟'));
      expect(report.workItems.single.progress, 0);
    },
  );

  test(
    'saved report and style snapshots remain unchanged after source edits',
    () async {
      final task = await tasks.createTask(
        const TaskDraft(title: 'RTL 交付', status: TaskStatus.planned),
      );
      await editor.complete(task);
      await PreferencesRepository(db).save(
        const AppPreferences(
          nickname: '工程师',
          importanceThreshold: 50,
          urgencyThreshold: 50,
        ),
      );
      final report = await build();
      await reports.save(report);
      now = DateTime(2026, 10, 20);
      await editor.save((await tasks.get(task.id))!, title: '修改后的标题');
      final historical = (await reports.get(report.id))!;
      expect(historical.workItems.single.text, 'RTL 交付');
      expect(historical.author, '工程师');
      expect(historical.style.workHeading, '本周主要工作内容:');
      expect(
        historical.workItems.single.evidence.first.title,
        contains('RTL 交付'),
      );
    },
  );
}
