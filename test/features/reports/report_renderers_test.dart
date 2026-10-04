import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/reports/report_evidence.dart';
import 'package:quadrant_planner/domain/reports/report_style_profile.dart';
import 'package:quadrant_planner/domain/reports/weekly_report.dart';
import 'package:quadrant_planner/features/reports/export/markdown_report_renderer.dart';
import 'package:quadrant_planner/features/reports/export/plain_text_report_renderer.dart';
import 'package:quadrant_planner/features/reports/export/xlsx_report_renderer.dart';

WeeklyReport sampleReport() {
  const ref = ReportEvidenceRef(
    id: 'task-t1',
    kind: 'task',
    sourceId: 't1',
    title: 'RTL dmac_regfile',
    detail: '完成',
  );
  return WeeklyReport(
    id: 'report',
    week: DateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 11)),
    author: '工程师',
    reportDate: DateTime(2026, 10, 9),
    style: ReportStyleProfile.standard(),
    workItems: [
      ReportItem(
        id: 'first',
        text: '完成 RTL dmac_regfile AXI 验证',
        progress: 100,
        projectId: 'p',
        projectName: '芯片项目',
        evidence: [ref],
      ),
      ReportItem(
        id: 'second',
        text: 'UVM dmac_intr 覆盖率',
        progress: 80,
        evidence: [ref],
      ),
    ],
    reflections: [
      ReportReflection(
        id: 'qa',
        question: 'AXI timeout',
        answer: '保留 transaction ID',
        evidence: [ref],
      ),
    ],
    nextWeekItems: [
      ReportItem(id: 'next', text: '补齐 UVM 回归', evidence: [ref]),
    ],
    createdAt: DateTime.utc(2026, 10, 9),
    updatedAt: DateTime.utc(2026, 10, 9),
  );
}

void main() {
  test(
    'all three renderers preserve identical approved technical content',
    () async {
      final report = sampleReport();
      final plain = PlainTextReportRenderer().render(report, report.style);
      final markdown = MarkdownReportRenderer().render(report, report.style);
      final bytes = await XlsxReportRenderer().render(report, report.style);
      final workbook = Excel.decodeBytes(bytes);
      final xlsx = workbook.tables.values.single.rows
          .map((row) => row.firstOrNull?.value?.toString() ?? '')
          .join('\n');
      List<String> normalized(String s) => s
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^#{1,6} '), '').trim())
          .where((line) => line.isNotEmpty)
          .toList();
      const expected = [
        '工作周报',
        '姓名：工程师',
        '汇报日期：2026-10-09',
        '本周主要工作内容:',
        '1. 完成 RTL dmac_regfile AXI 验证 [100%]',
        '2. UVM dmac_intr 覆盖率 [80%]',
        '本周工作遇到的困难 / 问题 / 体会 / 感受:',
        'Q1: AXI timeout',
        'A1: 保留 transaction ID',
        '下周工作计划:',
        '1. 补齐 UVM 回归',
        '主管反馈:',
      ];
      expect(normalized(plain), expected);
      expect(normalized(markdown), expected);
      expect(normalized(xlsx), expected);
      expect(plain, isNot(contains('芯片项目')));
      expect(plain.trimRight().endsWith('主管反馈:'), isTrue);
    },
  );
  test('empty reflection and next-week sections keep editable Q/A and numbered placeholders', () async {
    final report = sampleReport().copyWith(
      reflections: [],
      nextWeekItems: [],
      workItems: [],
    );
    final output = PlainTextReportRenderer().render(report, report.style);
    expect(output, contains('Q1:\nA1:'));
    expect(output, contains('下周工作计划:\n1.\n2.'));
    expect(output, isNot(contains('[100%]')));
  });
  test(
    'XLSX treats edited leading equals and technical names as literal text',
    () async {
      final source = sampleReport();
      final item = source.workItems.first.copyWith(
        text: '=RTL_dmac_regfile + UVM',
      );
      final report = source.copyWith(
        workItems: [item],
        supervisorFeedback: '请检查 AXI',
      );
      final workbook = Excel.decodeBytes(
        await XlsxReportRenderer().render(report, report.style),
      );
      final cells = workbook.tables.values.single.rows
          .expand((row) => row)
          .whereType<Data>()
          .toList();
      expect(cells.any((c) => c.value is FormulaCellValue), isFalse);
      expect(
        cells.any(
          (c) => c.value?.toString() == '1. =RTL_dmac_regfile + UVM [100%]',
        ),
        isTrue,
      );
      expect(cells.any((c) => c.value?.toString() == '请检查 AXI'), isTrue);
    },
  );
  test(
    'XLSX shows all explicit technical lines in a multiline work item',
    () async {
      final source = sampleReport();
      final report = source.copyWith(
        workItems: [
          source.workItems.first.copyWith(text: 'RTL\nUVM\nAXI\ndmac_regfile'),
        ],
      );
      final sheet = Excel.decodeBytes(
        await XlsxReportRenderer().render(report, report.style),
      ).tables.values.single;
      final row = sheet.rows.indexWhere(
        (r) => r.first?.value?.toString().contains('RTL\nUVM') ?? false,
      );
      expect(row, greaterThanOrEqualTo(0));
      expect(sheet.getRowHeight(row), greaterThanOrEqualTo(72));
    },
  );
}
