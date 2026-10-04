import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/weekly_report.dart';
import 'report_content.dart';

class PlainTextReportRenderer {
  String render(WeeklyReport report, ReportStyleProfile style) =>
      '${reportContent(report, style).map((line) => line.text).join('\n')}\n';
}
