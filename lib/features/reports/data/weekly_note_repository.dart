import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/reports/weekly_report.dart';

class WeeklyNote {
  final String id;
  final String? taskId;
  final DateTime weekStart;
  final String problem;
  final String cause;
  final String solution;
  final String learning;
  final DateTime createdAt;
  const WeeklyNote({
    required this.id,
    this.taskId,
    required this.weekStart,
    required this.problem,
    required this.cause,
    required this.solution,
    required this.learning,
    required this.createdAt,
  });
}

class WeeklyNoteRepository {
  final AppDatabase _db;
  final DateTime Function() _clock;
  final String Function() _idFactory;
  WeeklyNoteRepository(
    this._db, {
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? (() => const Uuid().v4());
  Future<WeeklyNote> add({
    String? taskId,
    required DateTime weekStart,
    String problem = '',
    String cause = '',
    String solution = '',
    String learning = '',
  }) async {
    final values = [
      problem,
      cause,
      solution,
      learning,
    ].map((v) => v.trim()).toList();
    if (values.every((v) => v.isEmpty)) throw ArgumentError('至少填写一项周报笔记');
    final note = WeeklyNote(
      id: _idFactory(),
      taskId: taskId,
      weekStart: DateRange.weekOf(weekStart).start,
      problem: values[0],
      cause: values[1],
      solution: values[2],
      learning: values[3],
      createdAt: _clock().toUtc(),
    );
    await _db
        .into(_db.weeklyNotes)
        .insert(
          WeeklyNotesCompanion.insert(
            id: note.id,
            weekStart: reportDate(note.weekStart),
            taskId: Value(taskId),
            problem: Value(note.problem),
            cause: Value(note.cause),
            solution: Value(note.solution),
            learning: Value(note.learning),
            createdAt: note.createdAt,
          ),
        );
    return note;
  }

  Future<List<WeeklyNote>> forWeek(DateTime weekStart) async =>
      (await (_db.select(_db.weeklyNotes)
                ..where(
                  (n) => n.weekStart.equals(
                    reportDate(DateRange.weekOf(weekStart).start),
                  ),
                )
                ..orderBy([
                  (n) => OrderingTerm.asc(n.createdAt),
                  (n) => OrderingTerm.asc(n.id),
                ]))
              .get())
          .map(_note)
          .toList();
  WeeklyNote _note(WeeklyNoteRow r) => WeeklyNote(
    id: r.id,
    taskId: r.taskId,
    weekStart: DateTime.parse(r.weekStart),
    problem: r.problem ?? '',
    cause: r.cause ?? '',
    solution: r.solution ?? '',
    learning: r.learning ?? '',
    createdAt: r.createdAt.toUtc(),
  );
}
