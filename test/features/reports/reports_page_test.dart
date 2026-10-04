import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/features/reports/application/reports_controller.dart';
import 'package:quadrant_planner/features/reports/data/report_file_gateway.dart';
import 'package:quadrant_planner/features/reports/data/report_repository.dart';
import 'package:quadrant_planner/features/reports/presentation/reports_page.dart';
import 'package:quadrant_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late ReportRepository reports;
  late ReportsController controller;
  late _Files files;
  Future<void> mount(WidgetTester tester) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    reports = ReportRepository(db, clock: () => DateTime(2026, 10, 9));
    files = _Files();
    controller = ReportsController(
      reports: reports,
      files: files,
      clock: () => DateTime(2026, 10, 9),
    );
    addTearDown(() async {
      controller.dispose();
      await db.close();
    });
    await TaskRepository(db, clock: () => DateTime(2026, 10, 6)).createTask(
      const TaskDraft(
        title: 'RTL dmac_regfile 验证',
        status: TaskStatus.inProgress,
        progress: 80,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ReportsPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成草稿'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'generate edit and evidence preview survive export cancellation and failure',
    (tester) async {
      await mount(tester);
      final field = find.byKey(const ValueKey('report-work-0'));
      await tester.enterText(field, 'RTL dmac_regfile 已补齐场景');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看依据').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看依据').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('inProgress · 80%'), findsWidgets);
      files.onSave = () async {
        expect(
          (await reports.get(controller.draft!.id))!.workItems.single.text,
          'RTL dmac_regfile 已补齐场景',
        );
      };
      await tester.scrollUntilVisible(
        find.text('导出 Markdown'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 Markdown'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('已取消导出，草稿已保存'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('已取消导出，草稿已保存'), findsOneWidget);
      files.fail = true;
      await tester.tap(find.text('导出 Markdown'));
      await tester.pumpAndSettle();
      expect(find.textContaining('导出失败'), findsOneWidget);
      expect(
        (await reports.get(controller.draft!.id))!.workItems.single.text,
        'RTL dmac_regfile 已补齐场景',
      );
    },
  );
  testWidgets('copy plain text matches canonical edited preview', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('report-work-0')),
      'UVM dmac_intr 覆盖率',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    final preview = tester
        .widget<SelectableText>(find.byKey(const ValueKey('report-preview')))
        .data;
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('复制纯文本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制纯文本'));
    await tester.pumpAndSettle();
    expect(files.copied, preview);
    expect(files.copied, contains('1. UVM dmac_intr 覆盖率 [80%]'));
    expect(files.copied!.trimRight().endsWith('主管反馈:'), isTrue);
  });
  testWidgets('opening saved history never regenerates source work', (
    tester,
  ) async {
    await mount(tester);
    final id = controller.draft!.id;
    final tasks = TaskRepository(db);
    final task = (await tasks.getTasks()).single;
    await tasks.save(
      task.copyWith(
        title: '后来的标题',
        progress: 100,
        updatedAt: DateTime(2026, 10, 20),
      ),
    );
    await controller.selectWeek(DateTime(2026, 10, 19));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ValueKey('report-history-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('report-history-$id')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('report-work-0')))
          .controller!
          .text,
      'RTL dmac_regfile 验证',
    );
    expect(controller.draft!.workItems.single.progress, 80);
  });
  testWidgets('manually recorded next week action is editable and evidenced', (
    tester,
  ) async {
    await mount(tester);
    await tester.scrollUntilVisible(
      find.text('添加下周行动'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加下周行动'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '下周行动'),
      '补齐 UVM dmac_intr 回归',
    );
    await tester.pump();
    await tester.tap(find.text('保存行动'));
    await tester.pumpAndSettle();
    expect(controller.preview, contains('1. 补齐 UVM dmac_intr 回归'));
    final saved = (await reports.get(controller.draft!.id))!;
    expect(saved.nextWeekItems.single.evidence.single.kind, 'manual');
    expect(
      saved.nextWeekItems.single.evidence.single.detail,
      '补齐 UVM dmac_intr 回归',
    );
  });
  testWidgets(
    'temporarily cleared item remains persisted when export validation fails',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byKey(const ValueKey('report-work-0')), '');
      await tester.pumpAndSettle();
      await controller.export(ReportExportFormat.markdown);
      await tester.pumpAndSettle();
      expect(
        (await reports.get(controller.draft!.id))!.workItems.single.text,
        '',
      );
      expect(controller.error, contains('内容不能为空'));
    },
  );
  testWidgets(
    'removing work QA and next actions preserves other edits and saved draft',
    (tester) async {
      await mount(tester);
      await controller.reports.notes.add(
        weekStart: controller.week.start,
        problem: 'AXI timeout',
        cause: '握手未完成',
      );
      await controller.generate();
      controller.addNextAction('误加的 UVM 场景');
      await controller.save();
      await tester.pumpAndSettle();
      for (final tooltip in ['移除工作事项', '移除 Q/A', '移除下周行动']) {
        await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byTooltip(tooltip),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
      }
      final saved = (await reports.get(controller.draft!.id))!;
      expect(saved.workItems, isEmpty);
      expect(saved.reflections, isEmpty);
      expect(saved.nextWeekItems, isEmpty);
      expect(saved.author, controller.draft!.author);
    },
  );
  testWidgets('Reports controls fit a narrow desktop window with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 700));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      return tester.binding.setSurfaceSize(null);
    });
    await mount(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('复制纯文本'));
    await tester.pumpAndSettle();
    expect(find.text('复制纯文本').hitTestable(), findsOneWidget);
  });
}

class _Files implements ReportFileGateway {
  bool fail = false;
  String? copied;
  Future<void> Function()? onSave;
  @override
  Future<bool> save({
    required String filename,
    required Uint8List bytes,
  }) async {
    await onSave?.call();
    if (fail) throw StateError('disk full');
    return false;
  }

  @override
  Future<ReportSample?> pickStyleSample() async => null;
  @override
  Future<void> copyPlainText(String value) async {
    copied = value;
  }
}
