import 'dart:convert';

typedef LegacyCalendarProvider = Future<LegacyCalendar> Function(String version);

class LegacySettings {
  final int importanceMin;
  final int importanceMax;
  final int urgencyMin;
  final int urgencyMax;
  final String calendarVersion;

  const LegacySettings({
    this.importanceMin = -10,
    this.importanceMax = 10,
    this.urgencyMin = -15,
    this.urgencyMax = 5,
    this.calendarVersion = 'cn-release-2026-v1',
  });

  factory LegacySettings.fromJson(Map<String, Object?> json) {
    return LegacySettings(
      importanceMin: (json['importance_min'] as num?)?.toInt() ?? -10,
      importanceMax: (json['importance_max'] as num?)?.toInt() ?? 10,
      urgencyMin: (json['urgency_min'] as num?)?.toInt() ?? -15,
      urgencyMax: (json['urgency_max'] as num?)?.toInt() ?? 5,
      calendarVersion:
          json['calendar_version']?.toString() ?? 'cn-release-2026-v1',
    );
  }
}

class LegacyTask {
  final String id;
  final String title;
  final String note;
  final int importance;
  final int urgencyAnchor;
  final DateTime urgencyAnchorAt;
  final DateTime createdAt;
  final List<String> tagIds;
  final String status;
  final DateTime? completedAt;
  final DateTime? deletedAt;

  const LegacyTask({
    required this.id,
    required this.title,
    required this.note,
    required this.importance,
    required this.urgencyAnchor,
    required this.urgencyAnchorAt,
    required this.createdAt,
    required this.tagIds,
    required this.status,
    required this.completedAt,
    required this.deletedAt,
  });

  factory LegacyTask.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('legacy task id is empty');
    }
    if (title.isEmpty) {
      throw const FormatException('legacy task title is empty');
    }

    return LegacyTask(
      id: id,
      title: title,
      note: json['note']?.toString() ?? '',
      importance: (json['importance'] as num).toInt(),
      urgencyAnchor: (json['urgency_anchor'] as num).toInt(),
      urgencyAnchorAt:
          DateTime.parse(json['urgency_anchor_at'] as String).toUtc(),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      tagIds: (json['tag_ids'] as List? ?? const <Object?>[])
          .map((value) => value.toString())
          .toList(growable: false),
      status: json['status']?.toString() ?? 'active',
      completedAt: _optionalDate(json['completed_at']),
      deletedAt: _optionalDate(json['deleted_at']),
    );
  }
}

class LegacyTag {
  final String id;
  final String name;
  final DateTime? archivedAt;

  const LegacyTag({
    required this.id,
    required this.name,
    required this.archivedAt,
  });

  factory LegacyTag.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) {
      throw const FormatException('legacy tag id/name is empty');
    }
    return LegacyTag(
      id: id,
      name: name,
      archivedAt: _optionalDate(json['archived_at']),
    );
  }
}

class LegacyEvent {
  final String id;
  final String taskId;
  final String type;
  final DateTime occurredAt;
  final String payloadJson;

  const LegacyEvent({
    required this.id,
    required this.taskId,
    required this.type,
    required this.occurredAt,
    required this.payloadJson,
  });

  factory LegacyEvent.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim() ?? '';
    final taskId = json['task_id']?.toString().trim() ?? '';
    if (id.isEmpty || taskId.isEmpty) {
      throw const FormatException('legacy event id/task id is empty');
    }
    return LegacyEvent(
      id: id,
      taskId: taskId,
      type: json['type']?.toString() ?? 'legacy',
      occurredAt: DateTime.parse(json['occurred_at'] as String).toUtc(),
      payloadJson: jsonEncode(json),
    );
  }
}

class LegacySkippedEntity {
  final String entityKind;
  final String entityId;
  final String reason;

  const LegacySkippedEntity({
    required this.entityKind,
    required this.entityId,
    required this.reason,
  });

  Map<String, Object?> toJson() => {
        'entity_kind': entityKind,
        'entity_id': entityId,
        'reason': reason,
      };
}

class LegacyMigrationPreview {
  final int taskCount;
  final int tagCount;
  final int eventCount;
  final List<LegacySkippedEntity> skipped;

  const LegacyMigrationPreview({
    required this.taskCount,
    required this.tagCount,
    required this.eventCount,
    required this.skipped,
  });
}

class LegacySnapshot {
  final String profileId;
  final LegacySettings settings;
  final List<LegacyTask> tasks;
  final List<LegacyTag> tags;
  final List<LegacyEvent> events;
  final List<LegacySkippedEntity> skipped;

  const LegacySnapshot({
    required this.profileId,
    required this.settings,
    required this.tasks,
    required this.tags,
    required this.events,
    required this.skipped,
  });
}

class LegacyCalendar {
  final Set<int> coveredYears;
  final Set<String> holidays;

  const LegacyCalendar({
    required this.coveredYears,
    required this.holidays,
  });

  factory LegacyCalendar.fromJsonString(String raw) {
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    return LegacyCalendar(
      coveredYears: (json['covered_years'] as List? ?? const <Object?>[])
          .map((value) => (value as num).toInt())
          .toSet(),
      holidays: (json['holiday_dates'] as List? ?? const <Object?>[])
          .map((value) => value.toString())
          .toSet(),
    );
  }

  bool isBusinessDay(DateTime date) {
    final localDate = DateTime(date.year, date.month, date.day);
    if (localDate.weekday == DateTime.saturday ||
        localDate.weekday == DateTime.sunday) {
      return false;
    }
    if (!coveredYears.contains(localDate.year)) {
      return true;
    }
    return !holidays.contains(_dateKey(localDate));
  }

  int businessDaysBetween(DateTime from, DateTime to) {
    var cursor = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(cursor)) {
      return 0;
    }

    var count = 0;
    while (cursor.isBefore(end)) {
      cursor = cursor.add(const Duration(days: 1));
      if (isBusinessDay(cursor)) {
        count += 1;
      }
    }
    return count;
  }

  static String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value.toString()).toUtc();
}
