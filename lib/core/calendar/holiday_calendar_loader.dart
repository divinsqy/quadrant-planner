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

  static HolidayCalendarData parse(
    String raw, {
    String? fallbackVersion,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('invalid holiday calendar JSON: $error');
    }

    if (decoded is! Map) {
      throw const FormatException('holiday calendar root must be an object');
    }
    final json = decoded.cast<String, Object?>();

    final years = json['covered_years'];
    final dates = json['holiday_dates'];
    if (years is! List) {
      throw const FormatException('covered_years must be a list');
    }
    if (dates is! List) {
      throw const FormatException('holiday_dates must be a list');
    }

    final coveredYears = <int>{};
    for (final value in years) {
      if (value is! num) {
        throw const FormatException('covered_years entries must be numbers');
      }
      coveredYears.add(value.toInt());
    }

    final holidays = <String>{};
    for (final value in dates) {
      if (value is! String) {
        throw const FormatException('holiday_dates entries must be strings');
      }
      holidays.add(value);
    }

    final versionValue = json['version'];
    if (versionValue != null && versionValue is! String) {
      throw const FormatException('version must be a string');
    }

    return HolidayCalendarData(
      version: (versionValue as String?) ?? fallbackVersion ?? '',
      coveredYears: Set.unmodifiable(coveredYears),
      holidays: Set.unmodifiable(holidays),
    );
  }

  Future<HolidayCalendarData> load(String version) async {
    final raw = await rootBundle.loadString('assets/calendars/$version.json');
    return parse(raw, fallbackVersion: version);
  }
}
