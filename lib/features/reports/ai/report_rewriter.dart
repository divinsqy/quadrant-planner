import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/weekly_report.dart';
import 'report_rewrite_guard.dart';

abstract interface class ReportRewriteClient {
  Future<WeeklyReportDraft> rewrite(
    WeeklyReportDraft draft,
    ReportStyleProfile style,
  );
}

class ReportRewriter {
  final ReportRewriteClient? client;
  final Duration timeout;
  final ReportRewriteGuard guard;
  String? lastWarning;
  ReportRewriter({
    this.client,
    this.timeout = const Duration(seconds: 20),
    ReportRewriteGuard? guard,
  }) : guard = guard ?? ReportRewriteGuard();
  bool get available => client != null;
  Future<WeeklyReportDraft> rewrite(
    WeeklyReportDraft draft,
    ReportStyleProfile style,
  ) async {
    lastWarning = null;
    if (client == null) return draft;
    try {
      final rewritten = await client!.rewrite(draft, style).timeout(timeout);
      if (!guard.accepts(draft, rewritten)) {
        lastWarning = 'AI 改写包含无法证实的事实，已保留本地草稿。';
        return draft;
      }
      return rewritten;
    } catch (_) {
      lastWarning = 'AI 改写未完成，已保留本地草稿。';
      return draft;
    }
  }
}
