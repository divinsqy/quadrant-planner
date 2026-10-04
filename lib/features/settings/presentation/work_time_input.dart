import '../../../domain/planning/work_schedule.dart';

String formatMinute(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
int parseMinute(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) throw ArgumentError('请输入 HH:mm 格式的时间');
  final hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  if (hour > 24 || minute > 59 || (hour == 24 && minute != 0)) {
    throw ArgumentError('时间必须在 00:00–24:00 内');
  }
  return hour * 60 + minute;
}

List<TimeWindow> parseWindows(String text) {
  if (text.trim().isEmpty) return [];
  return text.split(RegExp('[,，]')).map((part) {
    final pair = part.trim().split(RegExp('[-–—]'));
    if (pair.length != 2) throw ArgumentError('时段格式为 09:00–12:00');
    return TimeWindow(
      startMinutes: parseMinute(pair[0]),
      endMinutes: parseMinute(pair[1]),
    ).validate();
  }).toList();
}
