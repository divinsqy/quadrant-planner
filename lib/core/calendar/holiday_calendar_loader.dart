import 'dart:convert';

import 'package:flutter/services.dart';

class HolidayCalendarData {
  final String version;
  final Set<int> coveredYears;
  final Set<String> holidays;

  const HolidayCalendarData({
    required this.version,
    required this.coveredYears,
    required this.holidays,
  });
}

class HolidayCalendarLoader {
  const HolidayCalendarLoader();

  Future<HolidayCalendarData> load(String version) async {
    final raw = await rootBundle.loadString('assets/calendars/$version.json');
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();

    return HolidayCalendarData(
      version: json['version']?.toString() ?? version,
      coveredYears: (json['covered_years'] as List? ?? const <Object?>[])
          .map((value) => (value as num).toInt())
          .toSet(),
      holidays: (json['holiday_dates'] as List? ?? const <Object?>[])
          .map((value) => value.toString())
          .toSet(),
    );
  }
}
