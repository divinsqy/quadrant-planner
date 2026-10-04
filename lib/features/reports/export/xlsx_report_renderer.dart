import 'dart:isolate';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/weekly_report.dart';
import 'report_content.dart';

class XlsxReportRenderer {
  Future<Uint8List> render(WeeklyReport report, ReportStyleProfile style) =>
      Isolate.run(() {
        final workbook = Excel.createExcel();
        workbook.rename('Sheet1', '工作周报');
        final sheet = workbook['工作周报'];
        sheet.setColumnWidth(0, 100);
        final lines = reportContent(report, style);
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final heading =
              line.kind == ReportLineKind.heading ||
              line.kind == ReportLineKind.title;
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
          );
          cell.value = TextCellValue(line.text);
          cell.cellStyle = CellStyle(
            bold: heading,
            fontSize: line.kind == ReportLineKind.title ? 18 : 11,
            horizontalAlign: HorizontalAlign.Left,
            verticalAlign: VerticalAlign.Top,
            textWrapping: TextWrapping.WrapText,
          );
          sheet.setRowHeight(
            i,
            line.kind == ReportLineKind.blank
                ? 12
                : line.kind == ReportLineKind.title
                ? 30
                : 8.0 +
                      line.text
                              .split('\n')
                              .fold<int>(
                                0,
                                (count, text) =>
                                    count + 1 + text.runes.length ~/ 50,
                              ) *
                          18,
          );
        }
        final bytes = workbook.encode();
        if (bytes == null) throw StateError('XLSX 编码失败');
        return Uint8List.fromList(bytes);
      });
}
