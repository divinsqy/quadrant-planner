import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/models.dart';

void main() {
  test('default ranges match the product contract', () {
    const s = AppSettings();
    expect(s.importanceMin, -10);
    expect(s.importanceMax, 10);
    expect(s.urgencyMin, -15);
    expect(s.urgencyMax, 5);
  });

  test('weekends and holidays do not increase urgency', () {
    final c = BusinessCalendar(
      version: 'test',
      coveredYears: {2026},
      holidays: {'2026-01-01'},
    );
    final task = TaskRecord(
      id: 't',
      title: 'x',
      note: '',
      importance: 1,
      urgencyAnchor: 0,
      urgencyAnchorAt: DateTime.utc(2026, 1, 1),
      createdAt: DateTime.utc(2026, 1, 1),
      tagIds: const [],
      status: TaskStatus.active,
    );
    expect(c.urgency(task, DateTime.utc(2026, 1, 4)), 1);
  });

  test('task json roundtrip keeps event-sourced state', () {
    final task = TaskRecord(
      id: 'abc',
      title: '测试',
      note: 'note',
      importance: 2,
      urgencyAnchor: -1,
      urgencyAnchorAt: DateTime.utc(2026, 9, 1),
      createdAt: DateTime.utc(2026, 9, 1),
      tagIds: const ['tag'],
      status: TaskStatus.active,
    );
    final copy = TaskRecord.fromJson(task.toJson());
    expect(copy.id, task.id);
    expect(copy.title, task.title);
    expect(copy.tagIds, task.tagIds);
  });
}
