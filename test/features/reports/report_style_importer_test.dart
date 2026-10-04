import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/features/reports/application/report_style_service.dart';
import 'package:quadrant_planner/features/reports/data/report_repository.dart';
import 'package:quadrant_planner/features/reports/import/report_style_importer.dart';

void main() {
  final importer = ReportStyleImporter();
  test('MD and TXT samples extract headings and concise numbered Q/A style without importing sample facts', () async {
    final bytes = await File('test/fixtures/report_style_sample.md')
        .readAsBytes();
    for (final filename in ['style.md', 'style.txt']) {
      final style = await importer.importBytes(
        filename: filename,
        bytes: bytes,
      );
      expect(style.title, '工作周报');
      expect(style.authorLabel, '姓名');
      expect(style.dateLabel, '汇报日期');
      expect(style.workHeading, '本周主要工作内容:');
      expect(style.reflectionHeading, '本周工作遇到的困难 / 问题 / 体会 / 感受:');
      expect(style.nextWeekHeading, '下周工作计划:');
      expect(style.feedbackHeading, '主管反馈:');
      expect(style.completionFormat, '[xx%]');
      expect(style.reflectionFormat, 'Q/A');
      expect(style.projectHeadings, isFalse);
      expect(style.preserveTechnicalTerms, isTrue);
      expect(jsonEncode(style.toJson()), isNot(contains('回归场景')));
    }
  });
  test(
    'genuine BIFF8 XLS sample imports and preserves Chinese section names',
    () async {
      final bytes = await File('test/fixtures/report_style_sample.xls')
          .readAsBytes();
      expect(bytes.take(8), [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
      final style = await importer.importBytes(
        filename: 'legacy.xls',
        bytes: bytes,
      );
      expect(style.workHeading, '本周主要工作内容:');
      expect(style.completionFormat, '[xx%]');
      expect(style.reflectionFormat, 'Q/A');
    },
  );
  test(
    'XLSX uses magic bytes even when named XLS and decodes all worksheet text',
    () async {
      final sample = await File('test/fixtures/report_style_sample.md')
          .readAsLines();
      final workbook = Excel.createExcel();
      final sheet = workbook['Sheet1'];
      for (var i = 0; i < sample.length; i++) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i),
          TextCellValue(sample[i]),
        );
      }
      final style = await importer.importBytes(
        filename: 'renamed.xls',
        bytes: Uint8List.fromList(workbook.encode()!),
      );
      expect(style.feedbackHeading, '主管反馈:');
      expect(style.reflectionHeading, '本周工作遇到的困难 / 问题 / 体会 / 感受:');
    },
  );
  test(
    'UTF16 Windows TXT imports and malformed files preserve active profile',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final reports = ReportRepository(db);
      final service = ReportStyleService(reports, importer: importer);
      final sample = await File('test/fixtures/report_style_sample.md')
          .readAsString();
      final utf16 = BytesBuilder()..add([0xff, 0xfe]);
      for (final unit in sample.codeUnits) {
        utf16.add([unit & 0xff, unit >> 8]);
      }
      final good = await service.importSample(
        filename: 'Windows.txt',
        bytes: utf16.toBytes(),
      );
      expect((await reports.activeStyle()).id, good.id);
      for (final file in [
        ('bad.xlsx', Uint8List.fromList([0x50, 0x4b, 3, 4, 0])),
        ('bad.xls', Uint8List.fromList([1, 2, 3])),
        ('bad.md', Uint8List.fromList(utf8.encode('not a weekly report'))),
      ]) {
        await expectLater(
          service.importSample(filename: file.$1, bytes: file.$2),
          throwsA(isA<ReportStyleParseError>()),
        );
        expect((await reports.activeStyle()).id, good.id);
      }
      await reports.saveStyle(good.copyWith(workHeading: '本周工作成果:'));
      expect((await reports.activeStyle()).workHeading, '本周工作成果:');
    },
  );
  test('multi-column XLS and XLSX preserve cell boundaries without importing personal sample values', () async {
    final workbook = Excel.createExcel();
    final rows = <List<String>>[
      ['工作周报'],
      ['姓名：工程师', '汇报日期：2026-10-09'],
      ['本周主要工作内容:'],
      ['1.', 'RTL dmac_regfile AXI 验证', '[100%]'],
      ['2.', 'UVM dmac_intr 覆盖率', '[80%]'],
      ['本周工作遇到的困难 / 问题 / 体会 / 感受:'],
      ['Q1: AXI timeout', 'A1: 补齐 UVM 场景'],
      ['下周工作计划:'],
      ['1.', '补齐 RTL 回归'],
      ['主管反馈:'],
    ];
    for (final row in rows) {
      workbook['Sheet1'].appendRow(row.map(TextCellValue.new).toList());
    }
    for (final sample in [
      ('table.xlsx', Uint8List.fromList(workbook.encode()!)),
      (
        'table.xls',
        await File('test/fixtures/report_style_table.xls').readAsBytes(),
      ),
    ]) {
      final style = await importer.importBytes(
        filename: sample.$1,
        bytes: sample.$2,
      );
      expect(style.authorLabel, '姓名');
      expect(style.dateLabel, '汇报日期');
      expect(style.numbering, '.');
      expect(style.reflectionFormat, 'Q/A');
      expect(jsonEncode(style.toJson()), isNot(contains('工程师')));
      expect(jsonEncode(style.toJson()), isNot(contains('2026-10-09')));
    }
  });
}
