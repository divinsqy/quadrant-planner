import 'dart:convert';

enum TaskStatus { active, completed, deleted }

class AppSettings {
  final int importanceMin;
  final int importanceMax;
  final int urgencyMin;
  final int urgencyMax;
  final String calendarVersion;
  const AppSettings({
    this.importanceMin = -10,
    this.importanceMax = 10,
    this.urgencyMin = -15,
    this.urgencyMax = 5,
    this.calendarVersion = 'cn-release-2026-v1',
  });

  Map<String, Object?> toJson() => {
    'importance_min': importanceMin,
    'importance_max': importanceMax,
    'urgency_min': urgencyMin,
    'urgency_max': urgencyMax,
    'calendar_version': calendarVersion,
  };

  factory AppSettings.fromJson(Map<String, Object?> j) => AppSettings(
    importanceMin: (j['importance_min'] as num?)?.toInt() ?? -10,
    importanceMax: (j['importance_max'] as num?)?.toInt() ?? 10,
    urgencyMin: (j['urgency_min'] as num?)?.toInt() ?? -15,
    urgencyMax: (j['urgency_max'] as num?)?.toInt() ?? 5,
    calendarVersion: j['calendar_version'] as String? ?? 'cn-release-2026-v1',
  );
}

class TagRecord {
  final String id;
  final String name;
  final DateTime? archivedAt;
  const TagRecord({required this.id, required this.name, this.archivedAt});
  bool get archived => archivedAt != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'archived_at': archivedAt?.toUtc().toIso8601String(),
  };

  factory TagRecord.fromJson(Map<String, Object?> j) => TagRecord(
    id: j['id'] as String,
    name: j['name'] as String,
    archivedAt: j['archived_at'] == null
        ? null
        : DateTime.parse(j['archived_at'] as String).toUtc(),
  );
}

class TaskRecord {
  final String id;
  final String title;
  final String note;
  final int importance;
  final int urgencyAnchor;
  final DateTime urgencyAnchorAt;
  final DateTime createdAt;
  final List<String> tagIds;
  final TaskStatus status;
  final DateTime? completedAt;
  final DateTime? deletedAt;

  const TaskRecord({
    required this.id,
    required this.title,
    required this.note,
    required this.importance,
    required this.urgencyAnchor,
    required this.urgencyAnchorAt,
    required this.createdAt,
    required this.tagIds,
    required this.status,
    this.completedAt,
    this.deletedAt,
  });

  TaskRecord copyWith({
    String? title,
    String? note,
    int? importance,
    int? urgencyAnchor,
    DateTime? urgencyAnchorAt,
    List<String>? tagIds,
    TaskStatus? status,
    DateTime? completedAt,
    DateTime? deletedAt,
  }) => TaskRecord(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    importance: importance ?? this.importance,
    urgencyAnchor: urgencyAnchor ?? this.urgencyAnchor,
    urgencyAnchorAt: urgencyAnchorAt ?? this.urgencyAnchorAt,
    createdAt: createdAt,
    tagIds: tagIds ?? this.tagIds,
    status: status ?? this.status,
    completedAt: completedAt ?? this.completedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'importance': importance,
    'urgency_anchor': urgencyAnchor,
    'urgency_anchor_at': urgencyAnchorAt.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'tag_ids': tagIds,
    'status': status.name,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  factory TaskRecord.fromJson(Map<String, Object?> j) => TaskRecord(
    id: j['id'] as String,
    title: j['title'] as String,
    note: j['note'] as String? ?? '',
    importance: (j['importance'] as num).toInt(),
    urgencyAnchor: (j['urgency_anchor'] as num).toInt(),
    urgencyAnchorAt: DateTime.parse(j['urgency_anchor_at'] as String).toUtc(),
    createdAt: DateTime.parse(j['created_at'] as String).toUtc(),
    tagIds: (j['tag_ids'] as List? ?? const []).cast<String>(),
    status: TaskStatus.values.byName(j['status'] as String),
    completedAt: j['completed_at'] == null
        ? null
        : DateTime.parse(j['completed_at'] as String).toUtc(),
    deletedAt: j['deleted_at'] == null
        ? null
        : DateTime.parse(j['deleted_at'] as String).toUtc(),
  );
}

class TaskEvent {
  final String id;
  final String taskId;
  final String type;
  final DateTime occurredAt;
  final TaskRecord after;
  const TaskEvent({
    required this.id,
    required this.taskId,
    required this.type,
    required this.occurredAt,
    required this.after,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'task_id': taskId,
    'type': type,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'after': after.toJson(),
  };

  factory TaskEvent.fromJson(Map<String, Object?> j) => TaskEvent(
    id: j['id'] as String,
    taskId: j['task_id'] as String,
    type: j['type'] as String,
    occurredAt: DateTime.parse(j['occurred_at'] as String).toUtc(),
    after: TaskRecord.fromJson((j['after'] as Map).cast<String, Object?>()),
  );
}

class BusinessCalendar {
  final String version;
  final Set<int> coveredYears;
  final Set<String> holidays;
  const BusinessCalendar({
    required this.version,
    required this.coveredYears,
    required this.holidays,
  });

  factory BusinessCalendar.fromJsonString(String raw) {
    final j = (jsonDecode(raw) as Map).cast<String, Object?>();
    return BusinessCalendar(
      version: j['version'] as String,
      coveredYears: (j['covered_years'] as List).map((e) => (e as num).toInt()).toSet(),
      holidays: (j['holiday_dates'] as List).cast<String>().toSet(),
    );
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool covers(DateTime d) => coveredYears.contains(d.year);

  bool isBusinessDay(DateTime localDate) {
    final d = DateTime(localDate.year, localDate.month, localDate.day);
    if (!covers(d)) return false;
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) return false;
    return !holidays.contains(_key(d));
  }

  int? businessDaysBetween(DateTime fromUtc, DateTime toUtc) {
    final a = DateTime(fromUtc.year, fromUtc.month, fromUtc.day);
    final b = DateTime(toUtc.year, toUtc.month, toUtc.day);
    if (b.isBefore(a)) return 0;
    var cursor = a;
    var count = 0;
    while (cursor.isBefore(b)) {
      cursor = cursor.add(const Duration(days: 1));
      if (!covers(cursor)) return null;
      if (isBusinessDay(cursor)) count++;
    }
    return count;
  }

  int? urgency(TaskRecord task, DateTime atUtc) {
    final delta = businessDaysBetween(task.urgencyAnchorAt, atUtc);
    return delta == null ? null : task.urgencyAnchor + delta;
  }
}

class WeeklySummary {
  final DateTime from;
  final DateTime to;
  final int created;
  final int completed;
  final int activeAtEnd;
  final int taskDays;
  final Map<String, int> heatmap;
  const WeeklySummary({
    required this.from,
    required this.to,
    required this.created,
    required this.completed,
    required this.activeAtEnd,
    required this.taskDays,
    required this.heatmap,
  });
}
