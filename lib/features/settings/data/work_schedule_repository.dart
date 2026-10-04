import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/planning/work_calendar.dart';
import '../../../domain/planning/work_schedule.dart';

String localDateKey(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class WorkScheduleRepository {
  final AppDatabase _db;
  final WorkCalendar baseCalendar;
  WorkScheduleRepository(this._db, {WorkCalendar? baseCalendar})
    : baseCalendar =
          baseCalendar ??
          WorkCalendar(
            schedule: WorkSchedule.standard(),
            coveredYears: const {},
            holidays: const {},
          );

  Stream<WorkCalendar> watchCalendar() => _db
      .customSelect(
        'SELECT 1 FROM preferences UNION ALL SELECT 1 FROM work_schedule_windows UNION ALL SELECT 1 FROM weekend_overrides',
        readsFrom: {
          _db.preferences,
          _db.workScheduleWindows,
          _db.weekendOverrides,
        },
      )
      .watch()
      .asyncMap((_) => getCalendar());

  Future<WorkCalendar> getCalendar() => _db.transaction(() async {
    final preferences = await (_db.select(
      _db.preferences,
    )..where((p) => p.id.equals('default'))).getSingleOrNull();
    var schedule = baseCalendar.schedule;
    if (preferences?.workScheduleConfigured ?? false) {
      final rows = await (_db.select(
        _db.workScheduleWindows,
      )..where((w) => w.enabled.equals(true))).get();
      schedule = WorkSchedule(
        weekdayWindows: {
          for (var weekday = 1; weekday <= 5; weekday++)
            weekday: rows
                .where((w) => w.weekday == weekday)
                .map(
                  (w) => TimeWindow(
                    startMinutes: w.startMinutes,
                    endMinutes: w.endMinutes,
                  ),
                )
                .toList(),
        },
      );
    }
    final overrides = await _db.select(_db.weekendOverrides).get();
    final dates = overrides.map((row) => row.localDate).toSet();
    for (final date in dates) {
      schedule = schedule.withDateOverride(
        DateTime.parse(date),
        overrides
            .where((row) => row.localDate == date)
            .map(
              (row) => TimeWindow(
                startMinutes: row.startMinutes,
                endMinutes: row.endMinutes,
              ),
            )
            .toList(),
      );
    }
    return WorkCalendar(
      schedule: schedule,
      coveredYears: baseCalendar.coveredYears,
      holidays: baseCalendar.holidays,
    );
  });

  void _validate(List<TimeWindow> windows) {
    WorkSchedule(weekdayWindows: {1: windows});
    if (windows.any(
      (w) => w.startMinutes < 14 * 60 && w.endMinutes > 12 * 60,
    )) {
      throw ArgumentError('12:00–14:00 为午休，不可安排');
    }
  }

  Future<void> saveWeekdays(Map<int, List<TimeWindow>> windows) async {
    for (final entry in windows.entries) {
      if (entry.key < 1 || entry.key > 5) throw ArgumentError('周末只能使用单日临时时段');
      _validate(entry.value);
    }
    await _db.transaction(() async {
      await _db.delete(_db.workScheduleWindows).go();
      for (final entry in windows.entries) {
        for (var i = 0; i < entry.value.length; i++) {
          final w = entry.value[i];
          await _db
              .into(_db.workScheduleWindows)
              .insert(
                WorkScheduleWindowsCompanion.insert(
                  id: '${entry.key}-$i',
                  weekday: entry.key,
                  startMinutes: w.startMinutes,
                  endMinutes: w.endMinutes,
                ),
              );
        }
      }
      await _db
          .into(_db.preferences)
          .insert(
            PreferencesCompanion.insert(id: 'default'),
            mode: InsertMode.insertOrIgnore,
          );
      await (_db.update(
        _db.preferences,
      )..where((p) => p.id.equals('default'))).write(
        const PreferencesCompanion(workScheduleConfigured: Value(true)),
      );
    });
  }

  Future<void> setDateOverride(DateTime date, List<TimeWindow> windows) async {
    _validate(windows);
    if (windows.isEmpty) throw ArgumentError('至少添加一个时段，或移除临时覆盖');
    final key = localDateKey(date);
    await _db.transaction(() async {
      await (_db.delete(
        _db.weekendOverrides,
      )..where((r) => r.localDate.equals(key))).go();
      for (var i = 0; i < windows.length; i++) {
        final w = windows[i];
        await _db
            .into(_db.weekendOverrides)
            .insert(
              WeekendOverridesCompanion.insert(
                id: '$key-$i',
                localDate: key,
                startMinutes: w.startMinutes,
                endMinutes: w.endMinutes,
              ),
            );
      }
    });
  }

  Future<void> clearDateOverride(DateTime date) => (_db.delete(
    _db.weekendOverrides,
  )..where((r) => r.localDate.equals(localDateKey(date)))).go();
}
