import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/calendar/holiday_calendar_loader.dart';

void main() {
  test('parses the bundled holiday calendar schema', () {
    const raw = '''
    {
      "version": "cn-release-2026-v1",
      "covered_years": [2026],
      "holiday_dates": ["2026-10-01", "2026-10-02"]
    }
    ''';

    final calendar = HolidayCalendarLoader.parse(raw);

    expect(calendar.version, 'cn-release-2026-v1');
    expect(calendar.coveredYears, {2026});
    expect(calendar.holidays, {'2026-10-01', '2026-10-02'});
  });

  test('rejects malformed calendar payloads', () {
    expect(
      () => HolidayCalendarLoader.parse('{"covered_years":"2026"}'),
      throwsFormatException,
    );
  });
}
