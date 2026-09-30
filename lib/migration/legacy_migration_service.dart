import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

import '../core/database/app_database.dart';
import '../domain/tasks/task_status.dart';
import '../domain/tasks/workload.dart';
import 'legacy_models.dart';
import 'legacy_reader.dart';
import 'legacy_score_normalizer.dart';

class LegacyMigrationResult {
  final bool alreadyMigrated;
  final int importedTasks;
  final int importedTags;
  final int importedEvents;
  final String sourceHash;
  final List<LegacySkippedEntity> skipped;

  const LegacyMigrationResult({
    required this.alreadyMigrated,
    required this.importedTasks,
    required this.importedTags,
    required this.importedEvents,
    required this.sourceHash,
    required this.skipped,
  });
}

class LegacyMigrationService {
  final AppDatabase database;
  final String legacyDatabasePath;
  final LegacyCalendarProvider? calendarProvider;

  const LegacyMigrationService({
    required this.database,
    required this.legacyDatabasePath,
    this.calendarProvider,
  });

  Future<bool> hasSuccessfulMigration() async {
    final sourceFile = File(legacyDatabasePath);
    if (!await sourceFile.exists()) {
      return false;
    }
    final sourceHash = await _sourceHash(sourceFile);
    final rows = await (database.select(database.migrationState)
          ..where(
            (row) =>
                row.sourceHash.equals(sourceHash) & row.success.equals(true),
          ))
        .get();
    return rows.isNotEmpty;
  }

  Future<LegacyMigrationPreview> preview() async {
    final snapshot = await LegacyReader(legacyDatabasePath).read();
    return LegacyMigrationPreview(
      taskCount: snapshot.tasks.length,
      tagCount: snapshot.tags.length,
      eventCount: snapshot.events.length,
      skipped: List.unmodifiable(snapshot.skipped),
    );
  }

  Future<LegacyMigrationResult> migrate({
    required DateTime migrationAt,
  }) async {
    final migrationTime = migrationAt.toUtc();
    final sourceFile = File(legacyDatabasePath);
    final sourceHash = await _sourceHash(sourceFile);

    final prior = await (database.select(database.migrationState)
          ..where(
            (row) => row.sourceHash.equals(sourceHash) & row.success.equals(true),
          ))
        .get();
    if (prior.isNotEmpty) {
      return LegacyMigrationResult(
        alreadyMigrated: true,
        importedTasks: 0,
        importedTags: 0,
        importedEvents: 0,
        sourceHash: sourceHash,
        skipped: const [],
      );
    }

    final snapshot = await LegacyReader(legacyDatabasePath).read();
    final calendar = await _loadCalendar(
      snapshot.settings.calendarVersion,
      migrationTime,
    );
    final validTagIds = snapshot.tags.map((tag) => tag.id).toSet();
    final importedTaskIds = <String>{};

    var importedTags = 0;
    var importedTasks = 0;
    var importedEvents = 0;

    await database.transaction(() async {
      for (final tag in snapshot.tags) {
        final inserted = await database.into(database.tags).insert(
              TagsCompanion(
                id: Value(tag.id),
                name: Value(tag.name),
                archivedAt: Value(tag.archivedAt),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (inserted > 0) {
          importedTags += 1;
        }
      }

      for (final legacyTask in snapshot.tasks) {
        final status = _mapStatus(legacyTask.status);
        final legacyUrgency = legacyTask.urgencyAnchor +
            calendar.businessDaysBetween(
              legacyTask.urgencyAnchorAt,
              migrationTime,
            );
        final importance = normalizeLegacyScore(
          legacyTask.importance,
          snapshot.settings.importanceMin,
          snapshot.settings.importanceMax,
        );
        final urgency = normalizeLegacyScore(
          legacyUrgency,
          snapshot.settings.urgencyMin,
          snapshot.settings.urgencyMax,
        );

        final inserted = await database.into(database.tasks).insert(
              TasksCompanion(
                id: Value(legacyTask.id),
                title: Value(legacyTask.title),
                description: Value(legacyTask.note),
                status: Value(status.name),
                projectId: const Value(null),
                importance: Value(importance),
                baseUrgency: Value(urgency),
                baseUrgencyAnchorAt: Value(migrationTime),
                deadline: const Value(null),
                estimatedMinutes: const Value(null),
                workload: Value(Workload.medium.name),
                progress: Value(
                  status == TaskStatus.completed ? 100 : 0,
                ),
                includeInWeeklyReport: const Value(true),
                createdAt: Value(legacyTask.createdAt),
                updatedAt: Value(migrationTime),
                completedAt: Value(legacyTask.completedAt),
                deletedAt: Value(legacyTask.deletedAt),
                serverRevision: const Value(0),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (inserted > 0) {
          importedTasks += 1;
        }
        importedTaskIds.add(legacyTask.id);

        for (final tagId in legacyTask.tagIds) {
          if (!validTagIds.contains(tagId)) {
            continue;
          }
          await database.into(database.taskTags).insert(
                TaskTagsCompanion(
                  taskId: Value(legacyTask.id),
                  tagId: Value(tagId),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }

      for (final event in snapshot.events) {
        if (!importedTaskIds.contains(event.taskId)) {
          continue;
        }
        final inserted = await database.into(database.activityEvents).insert(
              ActivityEventsCompanion(
                id: Value(event.id),
                taskId: Value(event.taskId),
                type: Value(event.type),
                occurredAt: Value(event.occurredAt),
                payloadJson: Value(event.payloadJson),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (inserted > 0) {
          importedEvents += 1;
        }
      }

      await database.into(database.migrationState).insert(
            MigrationStateCompanion(
              id: Value('legacy-v0-$sourceHash'),
              sourcePath: Value(legacyDatabasePath),
              sourceHash: Value(sourceHash),
              migratedAt: Value(migrationTime),
              importedCountsJson: Value(
                jsonEncode({
                  'tasks': importedTasks,
                  'tags': importedTags,
                  'events': importedEvents,
                }),
              ),
              skippedJson: Value(
                jsonEncode(
                  snapshot.skipped.map((item) => item.toJson()).toList(),
                ),
              ),
              success: const Value(true),
            ),
            mode: InsertMode.insertOrReplace,
          );
    });

    final afterHash = sha256.convert(await sourceFile.readAsBytes()).toString();
    if (afterHash != sourceHash) {
      throw StateError('LEGACY_SOURCE_CHANGED_DURING_MIGRATION');
    }

    return LegacyMigrationResult(
      alreadyMigrated: false,
      importedTasks: importedTasks,
      importedTags: importedTags,
      importedEvents: importedEvents,
      sourceHash: sourceHash,
      skipped: List.unmodifiable(snapshot.skipped),
    );
  }

  Future<String> _sourceHash(File file) async {
    return sha256.convert(await file.readAsBytes()).toString();
  }

  Future<LegacyCalendar> _loadCalendar(
    String version,
    DateTime migrationAt,
  ) async {
    final provider = calendarProvider;
    if (provider != null) {
      return provider(version);
    }

    try {
      final raw = await rootBundle.loadString('assets/calendars/$version.json');
      return LegacyCalendar.fromJsonString(raw);
    } catch (_) {
      return LegacyCalendar(
        coveredYears: {migrationAt.year},
        holidays: const {},
      );
    }
  }

  TaskStatus _mapStatus(String legacyStatus) {
    switch (legacyStatus) {
      case 'active':
        return TaskStatus.planned;
      case 'completed':
        return TaskStatus.completed;
      case 'deleted':
        return TaskStatus.cancelled;
      default:
        throw FormatException('unsupported legacy status: $legacyStatus');
    }
  }
}
