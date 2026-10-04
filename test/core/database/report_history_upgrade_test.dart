import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/projects/milestone.dart';
import 'package:quadrant_planner/domain/reports/report_style_profile.dart';
import 'package:quadrant_planner/domain/reports/weekly_report.dart';
import 'package:quadrant_planner/features/projects/data/project_repository.dart';
import 'package:quadrant_planner/features/reports/application/weekly_report_builder.dart';
import 'package:quadrant_planner/features/reports/data/report_repository.dart';

void main() {
  test('v3 upgrade seeds milestone facts and preserves them across rename and database restart', () async {
    final folder = await Directory.systemTemp.createTemp(
      'quadrant-reports-upgrade-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/workspace.sqlite');
    final seed = AppDatabase.forTesting(NativeDatabase(file));
    final at = DateTime(2026, 10, 7);
    final projects = ProjectRepository(seed, clock: () => at);
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
        completedAt: at,
        createdAt: at,
        updatedAt: at,
      ),
    );
    await seed.close();
    final upgraded = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (db) {
          db.execute('DROP TABLE milestone_history');
          db.execute('PRAGMA user_version = 3');
        },
      ),
    );
    final later = DateTime(2026, 10, 20);
    final laterProjects = ProjectRepository(upgraded, clock: () => later);
    await laterProjects.saveMilestone(
      Milestone(
        id: milestone.id,
        projectId: project.id,
        name: 'CPU 未来目标',
        deadline: null,
        completedAt: at,
        createdAt: at,
        updatedAt: later,
      ),
    );
    await upgraded.close();
    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    final report = await WeeklyReportBuilder(
      reports: ReportRepository(reopened),
      clock: () => later,
    ).build(DateRange.weekOf(at), ReportStyleProfile.standard());
    expect(report.workItems.single.text, 'RTL AXI 交付');
    expect(report.workItems.single.evidence.single.detail, contains('升级前'));
    expect(
      (await laterProjectsFor(reopened, project.id)).single.name,
      'CPU 未来目标',
    );
  });
}

Future<List<Milestone>> laterProjectsFor(AppDatabase db, String id) =>
    ProjectRepository(db).watchMilestones(id).first;
