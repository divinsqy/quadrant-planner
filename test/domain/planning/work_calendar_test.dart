import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/work_calendar.dart';
import 'package:quadrant_planner/domain/planning/work_schedule.dart';

void main() {
  group('WorkCalendar', () {
    test('standard schedule exposes 09-12 and 14-18 on weekdays', () {
      final calendar = WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {2026},
        holidays: const {},
      );

      final monday = DateTime(2026, 9, 28);
      final decision = calendar.isWorkday(monday);
      final windows = calendar.availableWindows(monday);

      expect(decision.isWorkday, isTrue);
      expect(decision.isEstimated, isFalse);
      expect(
        windows,
        const [
          TimeWindow(startMinutes: 9 * 60, endMinutes: 12 * 60),
          TimeWindow(startMinutes: 14 * 60, endMinutes: 18 * 60),
        ],
      );
    });

    test('weekend and covered holiday are unavailable', () {
      final calendar = WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {2026},
        holidays: const {'2026-10-01'},
      );

      expect(calendar.isWorkday(DateTime(2026, 10, 1)).isWorkday, isFalse);
      expect(calendar.availableWindows(DateTime(2026, 10, 1)), isEmpty);
      expect(calendar.isWorkday(DateTime(2026, 10, 3)).isWorkday, isFalse);
      expect(calendar.availableWindows(DateTime(2026, 10, 3)), isEmpty);
    });

    test('one-date weekend override opens only that date', () {
      final schedule = WorkSchedule.standard().withDateOverride(
        DateTime(2026, 10, 3),
        const [TimeWindow(startMinutes: 10 * 60, endMinutes: 12 * 60)],
      );
      final calendar = WorkCalendar(
        schedule: schedule,
        coveredYears: const {2026},
        holidays: const {},
      );

      expect(calendar.isWorkday(DateTime(2026, 10, 3)).isWorkday, isTrue);
      expect(
        calendar.availableWindows(DateTime(2026, 10, 3)),
        const [TimeWindow(startMinutes: 10 * 60, endMinutes: 12 * 60)],
      );
      expect(calendar.availableWindows(DateTime(2026, 10, 4)), isEmpty);
    });

    test('uncovered year falls back to Monday-Friday and marks estimates', () {
      final calendar = WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {2026},
        holidays: const {},
      );

      final monday = calendar.isWorkday(DateTime(2027, 1, 4));
      final sunday = calendar.isWorkday(DateTime(2027, 1, 3));

      expect(monday.isWorkday, isTrue);
      expect(monday.isEstimated, isTrue);
      expect(sunday.isWorkday, isFalse);
      expect(sunday.isEstimated, isTrue);
    });

    test('workdaysBetween uses local calendar dates across DST-sized gaps', () {
      final calendar = WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {2026},
        holidays: const {},
      );

      final count = calendar.workdaysBetween(
        DateTime(2026, 10, 30, 23, 30),
        DateTime(2026, 11, 2, 0, 30),
      );

      expect(count.count, 1);
      expect(count.isEstimated, isFalse);
    });

    test('workdaysBetween propagates estimated flag for uncovered dates', () {
      final calendar = WorkCalendar(
        schedule: WorkSchedule.standard(),
        coveredYears: const {2026},
        holidays: const {},
      );

      final count = calendar.workdaysBetween(
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 4),
      );

      expect(count.count, 2);
      expect(count.isEstimated, isTrue);
    });
  });

  group('TimeWindow validation', () {
    test('rejects zero, reversed, and overlapping windows', () {
      expect(
        () => const TimeWindow(startMinutes: 60, endMinutes: 60).validate(),
        throwsArgumentError,
      );
      expect(
        () => const TimeWindow(startMinutes: 120, endMinutes: 60).validate(),
        throwsArgumentError,
      );
      expect(
        () => WorkSchedule(
          weekdayWindows: {
            DateTime.monday: const [
              TimeWindow(startMinutes: 9 * 60, endMinutes: 12 * 60),
              TimeWindow(startMinutes: 11 * 60, endMinutes: 13 * 60),
            ],
          },
        ),
        throwsArgumentError,
      );
    });
  });
}
