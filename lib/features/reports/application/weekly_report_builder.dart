import 'package:uuid/uuid.dart';

import '../../../domain/focus/focus_session.dart';
import '../../../domain/reports/report_evidence.dart';
import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/weekly_report.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_activity_event.dart';
import '../../../domain/tasks/task_status.dart';
import '../data/report_repository.dart';
import '../data/weekly_note_repository.dart';

class WeeklyReportBuilder {
  final ReportRepository reports;
  final DateTime Function() _clock;
  final String Function() _idFactory;
  WeeklyReportBuilder({
    required this.reports,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? (() => const Uuid().v4());

  Future<WeeklyReportDraft> build(
    DateRange week,
    ReportStyleProfile style,
  ) async {
    final facts = await reports.facts(week);
    final now = _clock();
    final work = <ReportItem>[];
    final next = <ReportItem>[];
    final reflections = <ReportReflection>[];
    for (final note in facts.notes) {
      reflections.add(
        ReportReflection(
          id: 'note-${note.id}',
          question: note.problem,
          answer: [
            if (note.cause.isNotEmpty) '原因：${note.cause}',
            if (note.solution.isNotEmpty) '解决：${note.solution}',
            if (note.learning.isNotEmpty) '体会：${note.learning}',
          ].join('；'),
          evidence: [_noteEvidence(note)],
        ),
      );
    }
    for (final current in facts.tasks) {
      if (!current.createdAt.isBefore(week.endExclusive) ||
          (current.deletedAt != null &&
              current.deletedAt!.isBefore(week.endExclusive))) {
        continue;
      }
      final events = facts.activity
          .where((a) => a.taskId == current.id)
          .toList();
      if (!current.updatedAt.isBefore(week.endExclusive) &&
          !events.any(
            (a) =>
                a.occurredAt.isAtSameMomentAs(current.updatedAt) &&
                a.payload['changes'] is Map,
          )) {
        // Raw imports/sync may have overwritten fields without recording old
        // values. Do not present the later state as a historical accomplishment.
        continue;
      }
      final task = _asOf(
        current,
        events.where((a) => !a.occurredAt.isBefore(week.endExclusive)).toList(),
      );
      if (!task.includeInWeeklyReport) continue;
      final inWeek = events.where((a) => week.contains(a.occurredAt)).toList();
      final taskNotes = facts.notes.where((n) => n.taskId == task.id).toList();
      final focused = <(FocusSession, Duration)>[];
      for (final session in facts.focus.where((s) => s.taskId == task.id)) {
        final duration = _focusDuring(session, week, now);
        if (duration > Duration.zero) focused.add((session, duration));
      }
      final completionEvent = inWeek.any((e) => e.type == 'completed');
      final completed =
          task.status == TaskStatus.completed &&
          (week.contains(task.completedAt) || completionEvent);
      final progressFact =
          task.progress > 0 &&
          (week.contains(task.createdAt) ||
              inWeek.any((a) => _changed(a, 'progress')));
      final manualInclude = inWeek.any(
        (a) => _after(a, 'includeInWeeklyReport') == true,
      );
      final solutionNotes = taskNotes
          .where((n) => n.solution.isNotEmpty)
          .toList();
      final evidence = <ReportEvidenceRef>[
        ReportEvidenceRef(
          id: 'task-${task.id}',
          kind: 'task',
          sourceId: task.id,
          title: task.title,
          detail: '${task.status.name} · ${completed ? 100 : task.progress}%',
          occurredAt: completed
              ? task.completedAt
              : week.contains(task.updatedAt)
              ? task.updatedAt
              : null,
        ),
        for (final a in inWeek.where(
          (a) =>
              a.type == 'completed' ||
              _changed(a, 'progress') ||
              _after(a, 'includeInWeeklyReport') == true,
        ))
          ReportEvidenceRef(
            id: 'activity-${a.id}',
            kind: 'activity',
            sourceId: a.id,
            title: task.title,
            detail: a.type == 'completed'
                ? '任务完成'
                : _changed(a, 'progress')
                ? '完成度：${_after(a, 'progress')}%'
                : '手动纳入周报',
            occurredAt: a.occurredAt,
          ),
        for (final f in focused)
          ReportEvidenceRef(
            id: 'focus-${f.$1.id}',
            kind: 'focus',
            sourceId: f.$1.id,
            title: task.title,
            detail: '本周专注 ${_minutes(f.$2)} 分钟',
            occurredAt: f.$1.startedAt,
          ),
        for (final n in taskNotes) _noteEvidence(n),
        if (task.projectId != null &&
            facts.projectNames.containsKey(task.projectId))
          ReportEvidenceRef(
            id: 'project-${task.projectId}',
            kind: 'project',
            sourceId: task.projectId!,
            title: facts.projectNames[task.projectId]!,
            detail: '所属项目',
          ),
      ];
      if (completed ||
          completionEvent ||
          progressFact ||
          manualInclude ||
          focused.isNotEmpty ||
          solutionNotes.isNotEmpty) {
        var text = task.title;
        if (!completed && !progressFact && solutionNotes.isNotEmpty) {
          text = solutionNotes.map((n) => n.solution).join('；');
        }
        if (!completed &&
            !progressFact &&
            solutionNotes.isEmpty &&
            focused.isNotEmpty) {
          final duration = focused.fold<Duration>(
            Duration.zero,
            (sum, item) => sum + item.$2,
          );
          text = '${task.title}（本周专注 ${_minutes(duration)} 分钟）';
        }
        work.add(
          ReportItem(
            id: 'task-${task.id}',
            text: text,
            progress: completed ? 100 : task.progress,
            projectId: task.projectId,
            projectName: facts.projectNames[task.projectId],
            evidence: evidence,
          ),
        );
      }
      if ((task.status == TaskStatus.planned ||
              task.status == TaskStatus.inProgress) &&
          (week.nextWeek.contains(task.deadline) ||
              facts.nextWeekPlanTaskIds.contains(task.id))) {
        next.add(
          ReportItem(
            id: 'next-${task.id}',
            text: task.title,
            projectId: task.projectId,
            projectName: facts.projectNames[task.projectId],
            evidence: [
              evidence.first,
              ReportEvidenceRef(
                id: 'plan-${task.id}',
                kind: 'plan',
                sourceId: task.id,
                title: task.title,
                detail: facts.nextWeekPlanTaskIds.contains(task.id)
                    ? '下周已保存的计划'
                    : '截止日期：${reportDate(task.deadline!.toLocal())}',
              ),
            ],
          ),
        );
      }
    }
    for (final milestone in facts.milestones.where(
      (m) => week.contains(m.completedAt),
    )) {
      final ref = ReportEvidenceRef(
        id: 'milestone-${milestone.id}',
        kind: 'milestone',
        sourceId: milestone.id,
        title: milestone.name,
        detail: milestone.historicalSeed ? '里程碑完成（升级前记录，名称取迁移时值）' : '里程碑完成',
        occurredAt: milestone.completedAt,
      );
      final duplicate = work.indexWhere(
        (i) => i.projectId == milestone.projectId && i.text == milestone.name,
      );
      if (duplicate >= 0) {
        final item = work[duplicate];
        work[duplicate] = ReportItem(
          id: item.id,
          text: item.text,
          progress: item.progress,
          projectId: item.projectId,
          projectName: item.projectName,
          evidence: [...item.evidence, ref],
        );
      } else {
        work.add(
          ReportItem(
            id: 'milestone-${milestone.id}',
            text: milestone.name,
            progress: 100,
            projectId: milestone.projectId,
            projectName: facts.projectNames[milestone.projectId],
            evidence: [ref],
          ),
        );
      }
    }
    for (final note in facts.notes.where(
      (n) => n.taskId == null && n.solution.isNotEmpty,
    )) {
      work.add(
        ReportItem(
          id: 'note-${note.id}',
          text: note.solution,
          evidence: [_noteEvidence(note)],
        ),
      );
    }
    int group(ReportItem a, ReportItem b) {
      final p = (a.projectName ?? '').compareTo(b.projectName ?? '');
      return p == 0 ? a.id.compareTo(b.id) : p;
    }

    work.sort(group);
    next.sort(group);
    return WeeklyReport(
      id: _idFactory(),
      week: week,
      author: facts.author,
      reportDate: now.toLocal(),
      style: style,
      workItems: work,
      reflections: reflections,
      nextWeekItems: next,
      createdAt: now.toUtc(),
      updatedAt: now.toUtc(),
    );
  }

  bool _changed(TaskActivityEvent a, String key) =>
      a.payload['changes'] is Map &&
      (a.payload['changes'] as Map).containsKey(key);
  Object? _after(TaskActivityEvent a, String key) =>
      _changed(a, key) ? (a.payload['changes'] as Map)[key]['after'] : null;
  ReportEvidenceRef _noteEvidence(WeeklyNote n) => ReportEvidenceRef(
    id: 'note-${n.id}',
    kind: 'note',
    sourceId: n.id,
    title: n.problem.isEmpty ? '本周笔记' : n.problem,
    detail: [
      n.problem,
      n.cause,
      n.solution,
      n.learning,
    ].where((s) => s.isNotEmpty).join('；'),
    occurredAt: n.createdAt,
  );
  String _minutes(Duration d) => d.inSeconds % 60 == 0
      ? '${d.inMinutes}'
      : (d.inSeconds / 60).toStringAsFixed(1);
  Duration _focusDuring(FocusSession session, DateRange week, DateTime now) {
    var seconds = 0;
    for (final interval in session.intervals) {
      final start = interval.start.isBefore(week.start)
          ? week.start
          : interval.start;
      var end = interval.end ?? now;
      if (end.isAfter(now)) end = now;
      if (end.isAfter(week.endExclusive)) end = week.endExclusive;
      if (end.isAfter(start)) seconds += end.difference(start).inSeconds;
    }
    return Duration(seconds: seconds);
  }

  Task _asOf(Task task, List<TaskActivityEvent> future) {
    final recordedOrder = {
      for (var i = 0; i < future.length; i++) future[i].id: i,
    };
    future.sort((a, b) {
      final time = b.occurredAt.compareTo(a.occurredAt);
      return time == 0
          ? recordedOrder[b.id]!.compareTo(recordedOrder[a.id]!)
          : time;
    });
    var result = task;
    for (final event in future) {
      final changes = event.payload['changes'];
      if (changes is! Map) continue;
      Object? before(String field) => (changes[field] as Map?)?['before'];
      result = result.copyWith(
        title: changes.containsKey('title') ? before('title') as String : null,
        progress: changes.containsKey('progress')
            ? before('progress') as int
            : null,
        status: changes.containsKey('status')
            ? TaskStatus.values.byName(before('status') as String)
            : null,
        includeInWeeklyReport: changes.containsKey('includeInWeeklyReport')
            ? before('includeInWeeklyReport') as bool
            : null,
        completedAt: changes.containsKey('completedAt')
            ? before('completedAt') == null
                  ? null
                  : DateTime.parse(before('completedAt') as String)
            : result.completedAt,
        projectId: changes.containsKey('projectId')
            ? before('projectId')
            : result.projectId,
        deadline: changes.containsKey('deadline')
            ? before('deadline') == null
                  ? null
                  : DateTime.parse(before('deadline') as String)
            : result.deadline,
      );
    }
    return result;
  }
}
