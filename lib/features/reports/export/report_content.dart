import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/weekly_report.dart';

enum ReportLineKind { title, heading, body, blank }

class ReportLine {
  final String text;
  final ReportLineKind kind;
  const ReportLine(this.text, [this.kind = ReportLineKind.body]);
}

List<ReportLine> reportContent(WeeklyReport report, ReportStyleProfile style) {
  const blank = ReportLine('', ReportLineKind.blank);
  final lines = <ReportLine>[
    ReportLine(style.title, ReportLineKind.title),
    ReportLine('${style.authorLabel}：${report.author}'),
    ReportLine('${style.dateLabel}：${reportDate(report.reportDate.toLocal())}'),
    blank,
    ReportLine(style.workHeading, ReportLineKind.heading),
  ];
  void items(List<ReportItem> items, {required bool withProgress}) {
    String? group;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (style.projectHeadings &&
          item.projectName != null &&
          group != item.projectName) {
        group = item.projectName;
        lines.add(ReportLine(group!, ReportLineKind.heading));
      }
      lines.add(
        ReportLine(
          '${i + 1}${style.numbering} ${item.text}${withProgress ? ' [${item.progress}%]' : ''}',
        ),
      );
    }
  }

  items(report.workItems, withProgress: true);
  lines.addAll([
    blank,
    ReportLine(style.reflectionHeading, ReportLineKind.heading),
  ]);
  if (report.reflections.isEmpty) {
    lines.addAll([const ReportLine('Q1:'), const ReportLine('A1:')]);
  } else {
    for (var i = 0; i < report.reflections.length; i++) {
      final qa = report.reflections[i];
      lines.addAll([
        ReportLine('Q${i + 1}:${qa.question.isEmpty ? '' : ' ${qa.question}'}'),
        ReportLine('A${i + 1}:${qa.answer.isEmpty ? '' : ' ${qa.answer}'}'),
      ]);
    }
  }
  lines.addAll([
    blank,
    ReportLine(style.nextWeekHeading, ReportLineKind.heading),
  ]);
  if (report.nextWeekItems.isEmpty) {
    lines.addAll([const ReportLine('1.'), const ReportLine('2.')]);
  } else {
    items(report.nextWeekItems, withProgress: false);
  }
  lines.addAll([
    blank,
    ReportLine(style.feedbackHeading, ReportLineKind.heading),
    ReportLine(report.supervisorFeedback),
  ]);
  return List.unmodifiable(lines);
}
