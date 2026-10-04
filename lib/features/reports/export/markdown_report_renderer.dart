import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/weekly_report.dart';
import 'report_content.dart';

class MarkdownReportRenderer {
  String render(WeeklyReport report, ReportStyleProfile style) =>
      '${reportContent(report, style).map((line) => switch (line.kind) {
        ReportLineKind.title => '# ${line.text}',
        ReportLineKind.heading => '## ${line.text}',
        _ => line.text,
      }).join('\n')}\n';
}
