import '../../../domain/reports/report_style_profile.dart';

class MarkdownStyleParser {
  ReportStyleProfile parse(
    String text, {
    required String id,
    required String name,
  }) {
    final lines = text
        .replaceAll('\r', '')
        .split('\n')
        .map((s) => s.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
    String heading(bool Function(String) accepts) =>
        lines.firstWhere(accepts, orElse: () => '');
    final title = heading(
      (s) => s.contains('周报') && !s.contains(':') && !s.contains('：'),
    );
    final author = heading(
      (s) =>
          RegExp(r'^(姓名|汇报人)\b').hasMatch(s) ||
          s.startsWith('姓名') ||
          s.startsWith('汇报人'),
    );
    final date = heading((s) => RegExp(r'^(汇报日期|报告日期|日期)').hasMatch(s));
    final reflection = heading(
      (s) => s.startsWith('本周') && RegExp(r'困难|问题|体会|感受|复盘').hasMatch(s),
    );
    final work = heading(
      (s) =>
          s.startsWith('本周') &&
          RegExp(r'工作|成果|事项').hasMatch(s) &&
          s != reflection,
    );
    final next = heading(
      (s) => s.startsWith('下周') && RegExp(r'计划|工作|安排').hasMatch(s),
    );
    final feedback = heading((s) => RegExp(r'^(主管|领导).*反馈').hasMatch(s));
    final numbered = lines.any((s) => RegExp(r'^\d+[.、)]').hasMatch(s));
    final progress = lines.any((s) => RegExp(r'\[\d{1,3}%\]').hasMatch(s));
    final qa =
        lines.any((s) => RegExp(r'^Q\d*[:：]').hasMatch(s)) &&
        lines.any((s) => RegExp(r'^A\d*[:：]').hasMatch(s));
    if ([
          title,
          author,
          date,
          work,
          reflection,
          next,
          feedback,
        ].any((s) => s.isEmpty) ||
        !numbered ||
        !progress ||
        !qa) {
      throw const FormatException('样本需包含姓名、日期、工作事项[xx%]、Q/A、下周计划及主管反馈');
    }
    String metadataLabel(String s, String pattern) =>
        RegExp(pattern).firstMatch(s)!.group(0)!;
    String sectionLabel(String s) {
      final delimiter = RegExp('[:：]').firstMatch(s);
      return delimiter == null ? s : s.substring(0, delimiter.end).trim();
    }

    return ReportStyleProfile(
      id: id,
      name: name,
      title: title,
      authorLabel: metadataLabel(author, r'^(姓名|汇报人)'),
      dateLabel: metadataLabel(date, r'^(汇报日期|报告日期|日期)'),
      workHeading: sectionLabel(work),
      reflectionHeading: sectionLabel(reflection),
      nextWeekHeading: sectionLabel(next),
      feedbackHeading: sectionLabel(feedback),
      numbering: RegExp(r'^\d+([.、)])')
          .firstMatch(
            lines.firstWhere((s) => RegExp(r'^\d+[.、)]').hasMatch(s)),
          )!
          .group(1)!,
    );
  }
}
