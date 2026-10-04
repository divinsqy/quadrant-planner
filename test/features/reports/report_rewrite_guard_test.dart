import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/reports/report_evidence.dart';
import 'package:quadrant_planner/domain/reports/report_style_profile.dart';
import 'package:quadrant_planner/domain/reports/weekly_report.dart';
import 'package:quadrant_planner/features/reports/ai/report_rewrite_guard.dart';
import 'package:quadrant_planner/features/reports/ai/report_rewriter.dart';

WeeklyReport factReport() => WeeklyReport(
  id: 'local',
  week: DateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 11)),
  author: '工程师',
  reportDate: DateTime(2026, 10, 9),
  style: ReportStyleProfile.standard(),
  workItems: [
    ReportItem(
      id: 'item',
      text: 'RTL dmac_regfile AXI 验证',
      progress: 100,
      evidence: [
        const ReportEvidenceRef(
          id: 'task-evidence',
          kind: 'task',
          sourceId: 'task',
          title: 'RTL dmac_regfile AXI 验证',
          detail: 'completed · 100%',
        ),
      ],
    ),
  ],
  reflections: [],
  nextWeekItems: [],
  createdAt: DateTime.utc(2026, 10, 9),
  updatedAt: DateTime.utc(2026, 10, 9),
);

void main() {
  final guard = ReportRewriteGuard();
  test(
    'accepts conservative wording changes retaining all facts and evidence',
    () {
      final original = factReport();
      final rewritten = original.copyWith(
        workItems: [
          original.workItems.single.copyWith(
            text: '完成 RTL dmac_regfile AXI 验证。',
          ),
        ],
      );
      expect(guard.accepts(original, rewritten), isTrue);
    },
  );
  test('rejects new accomplishment with unknown or missing evidence', () {
    final original = factReport();
    for (final refs in [
      <ReportEvidenceRef>[],
      [
        const ReportEvidenceRef(
          id: 'unknown',
          kind: 'task',
          sourceId: 'unknown',
          title: 'CPU 验证',
          detail: '完成',
        ),
      ],
    ]) {
      final added = ReportItem(
        id: 'new',
        text: 'CPU 验证',
        progress: 100,
        evidence: refs,
      );
      expect(
        guard.accepts(
          original,
          original.copyWith(workItems: [...original.workItems, added]),
        ),
        isFalse,
      );
    }
  });
  test('punctuation edits cannot invert a statement even with unchanged words and evidence', () {
    final source = factReport();
    final original = source.copyWith(
      workItems: [source.workItems.single.copyWith(text: '没有 RTL 错误')],
    );
    expect(
      guard.accepts(
        original,
        original.copyWith(
          workItems: [original.workItems.single.copyWith(text: '没，有 RTL 错误')],
        ),
      ),
      isFalse,
    );
    expect(
      guard.accepts(
        original,
        original.copyWith(
          workItems: [original.workItems.single.copyWith(text: '没有 RTL 错误？')],
        ),
      ),
      isFalse,
    );
  });
  test('valid evidence ID does not authorize unsupported new facts or identifier changes', () {
    final original = factReport();
    for (final text in [
      'RTL dmac_regfile AXI 验证，性能提升20%',
      '完成 CPU 流片',
      'RTL dmac_intr AXI 验证',
      'RTL DMAC_REGFILE AXI 验证',
      '未完成 RTL dmac_regfile AXI 验证',
    ]) {
      expect(
        guard.accepts(
          original,
          original.copyWith(
            workItems: [original.workItems.single.copyWith(text: text)],
          ),
        ),
        isFalse,
        reason: text,
      );
    }
  });
  test('progress and evidence snapshots cannot be modified or rebound', () {
    final original = factReport();
    expect(
      guard.accepts(
        original,
        original.copyWith(
          workItems: [original.workItems.single.copyWith(progress: 80)],
        ),
      ),
      isFalse,
    );
    final item = ReportItem(
      id: 'item',
      text: original.workItems.single.text,
      progress: 100,
      evidence: [
        const ReportEvidenceRef(
          id: 'task-evidence',
          kind: 'task',
          sourceId: 'other-task',
          title: 'RTL dmac_regfile AXI 验证',
          detail: 'completed · 100%',
        ),
      ],
    );
    expect(
      guard.accepts(original, original.copyWith(workItems: [item])),
      isFalse,
    );
    expect(
      guard.accepts(original, original.copyWith(supervisorFeedback: '主管已批准流片')),
      isFalse,
    );
  });
  test('cannot label partial work completed or add unsupported Q/A', () {
    final source = factReport();
    final original = source.copyWith(
      workItems: [source.workItems.single.copyWith(progress: 60)],
    );
    expect(
      guard.accepts(
        original,
        original.copyWith(
          workItems: [
            original.workItems.single.copyWith(
              text: '完成 RTL dmac_regfile AXI 验证',
            ),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      guard.accepts(
        original,
        original.copyWith(
          reflections: [
            ReportReflection(
              id: 'new',
              question: '客户已验收？',
              answer: '是',
              evidence: original.workItems.single.evidence,
            ),
          ],
        ),
      ),
      isFalse,
    );
  });
  test('network errors, timeout and invalid outputs return original local draft unchanged', () async {
    final original = factReport();
    for (final client in [
      _Client((_) => Future.error(StateError('offline'))),
      _Client((_) => Completer<WeeklyReport>().future),
      _Client(
        (r) async => r.copyWith(
          workItems: [r.workItems.single.copyWith(text: 'CPU 流片已完成')],
        ),
      ),
    ]) {
      final rewriter = ReportRewriter(
        client: client,
        timeout: const Duration(milliseconds: 10),
      );
      final result = await rewriter.rewrite(original, original.style);
      expect(identical(result, original), isTrue);
      expect(rewriter.lastWarning, isNotNull);
    }
  });
  test('local-only mode returns unchanged draft and configured adapter accepts safe edits', () async {
    final original = factReport();
    expect(
      await ReportRewriter().rewrite(original, original.style),
      same(original),
    );
    final rewriter = ReportRewriter(
      client: _Client(
        (r) async => r.copyWith(
          workItems: [
            r.workItems.single.copyWith(text: '完成 RTL dmac_regfile AXI 验证'),
          ],
        ),
      ),
    );
    final rewritten = await rewriter.rewrite(original, original.style);
    expect(rewritten.workItems.single.text, '完成 RTL dmac_regfile AXI 验证');
    expect(rewriter.lastWarning, isNull);
  });
}

class _Client implements ReportRewriteClient {
  final Future<WeeklyReport> Function(WeeklyReport) operation;
  _Client(this.operation);
  @override
  Future<WeeklyReport> rewrite(WeeklyReport draft, ReportStyleProfile style) =>
      operation(draft);
}
