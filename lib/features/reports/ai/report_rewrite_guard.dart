import 'dart:convert';

import '../../../domain/reports/weekly_report.dart';

/// Evidence IDs establish provenance, not semantic support for arbitrary prose.
/// Accept only verifiable presentation edits; uncertain paraphrases fail closed.
class ReportRewriteGuard {
  bool accepts(WeeklyReport original, WeeklyReport rewritten) {
    final before = original.toJson()
      ..remove('workItems')
      ..remove('reflections')
      ..remove('nextWeekItems');
    final after = rewritten.toJson()
      ..remove('workItems')
      ..remove('reflections')
      ..remove('nextWeekItems');
    if (jsonEncode(before) != jsonEncode(after)) return false;
    bool items(List<ReportItem> a, List<ReportItem> b, {required bool work}) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        final left = a[i].toJson()..remove('text');
        final right = b[i].toJson()..remove('text');
        if (b[i].evidence.isEmpty ||
            jsonEncode(left) != jsonEncode(right) ||
            !_phrase(
              a[i].text,
              b[i].text,
              completed: work && a[i].progress == 100,
            )) {
          return false;
        }
      }
      return true;
    }

    if (!items(original.workItems, rewritten.workItems, work: true) ||
        !items(original.nextWeekItems, rewritten.nextWeekItems, work: false) ||
        original.reflections.length != rewritten.reflections.length) {
      return false;
    }
    for (var i = 0; i < original.reflections.length; i++) {
      final a = original.reflections[i];
      final b = rewritten.reflections[i];
      final before = a.toJson()
        ..remove('question')
        ..remove('answer');
      final after = b.toJson()
        ..remove('question')
        ..remove('answer');
      if (b.evidence.isEmpty ||
          jsonEncode(before) != jsonEncode(after) ||
          !_phrase(a.question, b.question) ||
          !_phrase(a.answer, b.answer)) {
        return false;
      }
    }
    return true;
  }

  bool _phrase(String a, String b, {bool completed = false}) {
    String tokens(String value, String pattern) =>
        RegExp(pattern).allMatches(value).map((m) => m.group(0)).join('|');
    if (tokens(a, r'[A-Za-z_][A-Za-z0-9_.-]*') !=
            tokens(b, r'[A-Za-z_][A-Za-z0-9_.-]*') ||
        tokens(a, r'\d+(?:\.\d+)?%?') != tokens(b, r'\d+(?:\.\d+)?%?')) {
      return false;
    }
    String normalize(String value) {
      var s = value.trim();
      if (completed) s = s.replaceFirst(RegExp(r'^(已完成|完成了|完成)\s*'), '');
      // Only presentation changes are verifiable. Moving punctuation inside a
      // Chinese statement can invert its meaning without changing its words.
      return s
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('，', ',')
          .replaceAll('；', ';')
          .replaceAll('：', ':')
          .replaceFirst(RegExp(r'[。.]+$'), '');
    }

    return normalize(a) == normalize(b);
  }
}
