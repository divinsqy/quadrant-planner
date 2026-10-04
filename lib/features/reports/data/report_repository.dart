import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/focus/focus_session.dart';
import '../../../domain/projects/milestone.dart';
import '../../../domain/reports/weekly_report.dart';
import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_activity_event.dart';
import '../../settings/data/preferences_repository.dart';
import '../../tasks/data/task_repository.dart';
import 'weekly_note_repository.dart';

class ReportFacts {
  final List<Task> tasks;
  final List<TaskActivityEvent> activity;
  final List<FocusSession> focus;
  final List<WeeklyNote> notes;
  final List<Milestone> milestones;
  final Map<String, String> projectNames;
  final Set<String> nextWeekPlanTaskIds;
  final String author;
  const ReportFacts({
    required this.tasks,
    required this.activity,
    required this.focus,
    required this.notes,
    required this.milestones,
    required this.projectNames,
    required this.nextWeekPlanTaskIds,
    required this.author,
  });
}

class ReportRepository {
  final AppDatabase _db;
  final DateTime Function() _clock;
  late final notes = WeeklyNoteRepository(_db, clock: _clock);
  ReportRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  Future<ReportFacts> facts(DateRange week) => _db.transaction(() async {
    final tasks = await TaskRepository(_db).getTasks(includeDeleted: true);
    // UUIDs are not chronology. SQLite stores append-only activity in insertion
    // order, which also disambiguates edits sharing its second-level timestamp.
    final events =
        await (_db.select(_db.activityEvents)
              ..where(
                (e) => e.occurredAt.isBiggerOrEqualValue(week.start.toUtc()),
              )
              ..orderBy([
                (e) => OrderingTerm.asc(e.occurredAt),
                (e) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
              ]))
            .get();
    final focus = await _db.select(_db.focusSessions).get();
    final projects = await _db.select(_db.projects).get();
    final milestoneChanges =
        await (_db.select(_db.milestoneHistory)
              ..where(
                (m) =>
                    m.occurredAt.isSmallerThanValue(week.endExclusive.toUtc()),
              )
              ..orderBy([
                (m) => OrderingTerm.desc(m.occurredAt),
                (m) => OrderingTerm.desc(m.id),
              ]))
            .get();
    final milestones = <String, MilestoneHistoryRow>{};
    for (final row in milestoneChanges) {
      milestones.putIfAbsent(row.milestoneId, () => row);
    }
    final plans =
        await (_db.select(_db.dailyPlanBlocks)..where(
              (b) =>
                  b.localDate.isBiggerOrEqualValue(
                    reportDate(week.nextWeek.start),
                  ) &
                  b.localDate.isSmallerOrEqualValue(
                    reportDate(week.nextWeek.end),
                  ),
            ))
            .get();
    return ReportFacts(
      tasks: tasks,
      activity: events
          .map(
            (r) => TaskActivityEvent(
              id: r.id,
              taskId: r.taskId,
              type: r.type,
              occurredAt: r.occurredAt.toUtc(),
              payload: Map<String, dynamic>.from(
                jsonDecode(r.payloadJson) as Map,
              ),
            ),
          )
          .toList(),
      focus: focus
          .map(
            (r) => FocusSession(
              id: r.id,
              taskId: r.taskId,
              planBlockId: r.planBlockId,
              state: FocusSessionState.values.byName(r.state),
              startedAt: r.startedAt.toUtc(),
              endedAt: r.endedAt?.toUtc(),
              intervals: (jsonDecode(r.intervalsJson) as List)
                  .map(
                    (i) => FocusInterval(
                      start: DateTime.parse(i['start'] as String),
                      end: i['end'] == null
                          ? null
                          : DateTime.parse(i['end'] as String),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      notes: await WeeklyNoteRepository(_db).forWeek(week.start),
      milestones: milestones.values
          .map(
            (r) => Milestone(
              id: r.milestoneId,
              projectId: r.projectId,
              name: r.name,
              deadline: r.deadline,
              completedAt: r.completedAt,
              createdAt: r.createdAt,
              updatedAt: r.occurredAt,
              historicalSeed: r.isLegacySeed,
            ),
          )
          .toList(),
      projectNames: {for (final p in projects) p.id: p.name},
      nextWeekPlanTaskIds: plans.map((b) => b.taskId).toSet(),
      author: (await PreferencesRepository(_db).get()).nickname,
    );
  });

  Future<void> save(WeeklyReport report) async {
    for (final item in [...report.workItems, ...report.nextWeekItems]) {
      if (item.evidence.isEmpty) {
        throw ArgumentError('报告条目必须保留事实依据');
      }
      if (report.status == ReportStatus.finalized && item.text.trim().isEmpty) {
        throw ArgumentError('报告条目内容不能为空');
      }
    }
    if (report.reflections.any((r) => r.evidence.isEmpty)) {
      throw ArgumentError('复盘必须保留笔记依据');
    }
    final saved = report.copyWith(updatedAt: _clock().toUtc());
    await _db
        .into(_db.weeklyReports)
        .insertOnConflictUpdate(
          WeeklyReportsCompanion.insert(
            id: saved.id,
            fromDate: reportDate(saved.week.start),
            toDate: reportDate(saved.week.end),
            status: Value(saved.status.name),
            contentJson: jsonEncode(saved.toJson()),
            createdAt: saved.createdAt.toUtc(),
            updatedAt: saved.updatedAt.toUtc(),
          ),
        );
  }

  Future<WeeklyReport?> get(String id) async {
    final r = await (_db.select(
      _db.weeklyReports,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    return r == null ? null : _report(r);
  }

  Stream<List<WeeklyReport>> watchHistory() =>
      (_db.select(_db.weeklyReports)..orderBy([
            (r) => OrderingTerm.desc(r.fromDate),
            (r) => OrderingTerm.desc(r.updatedAt),
            (r) => OrderingTerm.asc(r.id),
          ]))
          .watch()
          .map((rows) => rows.map(_report).toList());
  Future<List<WeeklyReport>> history() async =>
      (await (_db.select(_db.weeklyReports)..orderBy([
                (r) => OrderingTerm.desc(r.fromDate),
                (r) => OrderingTerm.desc(r.updatedAt),
              ]))
              .get())
          .map(_report)
          .toList();
  WeeklyReport _report(WeeklyReportRow r) => WeeklyReport.fromJson(
    Map<String, dynamic>.from(jsonDecode(r.contentJson) as Map),
  );
  Future<ReportStyleProfile> activeStyle() async {
    final row =
        await (_db.select(_db.reportStyleProfiles)
              ..where((r) => r.isActive.equals(true))
              ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null
        ? ReportStyleProfile.standard()
        : ReportStyleProfile.fromJson(
            Map<String, dynamic>.from(jsonDecode(row.profileJson) as Map),
          );
  }

  Future<void> saveStyle(ReportStyleProfile style) => _db.transaction(() async {
    if ([
      style.name,
      style.title,
      style.authorLabel,
      style.dateLabel,
      style.workHeading,
      style.reflectionHeading,
      style.nextWeekHeading,
      style.feedbackHeading,
    ].any((s) => s.trim().isEmpty)) {
      throw ArgumentError('样式名称及标题不能为空');
    }
    final now = _clock().toUtc();
    final old = await (_db.select(
      _db.reportStyleProfiles,
    )..where((r) => r.id.equals(style.id))).getSingleOrNull();
    await _db
        .update(_db.reportStyleProfiles)
        .write(const ReportStyleProfilesCompanion(isActive: Value(false)));
    await _db
        .into(_db.reportStyleProfiles)
        .insertOnConflictUpdate(
          ReportStyleProfilesCompanion.insert(
            id: style.id,
            name: style.name,
            profileJson: jsonEncode(style.toJson()),
            isActive: const Value(true),
            createdAt: old?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  });
}
