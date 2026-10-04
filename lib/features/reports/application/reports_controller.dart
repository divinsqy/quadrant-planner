import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/report_evidence.dart';
import '../../../domain/reports/weekly_report.dart';
import '../ai/report_rewriter.dart';
import '../data/report_file_gateway.dart';
import '../data/report_repository.dart';
import '../export/markdown_report_renderer.dart';
import '../export/plain_text_report_renderer.dart';
import '../export/xlsx_report_renderer.dart';
import 'report_style_service.dart';
import 'weekly_report_builder.dart';

enum ReportExportFormat { markdown, xlsx }

class ReportsController extends ChangeNotifier {
  final ReportRepository reports;
  final ReportFileGateway files;
  final ReportRewriter rewriter;
  final DateTime Function() _clock;
  late DateRange week;
  ReportStyleProfile style = ReportStyleProfile.standard();
  WeeklyReport? draft;
  List<WeeklyReport> history = const [];
  bool busy = false;
  String? error;
  String? notice;
  bool _disposed = false;
  bool _started = false;
  StreamSubscription<List<WeeklyReport>>? _history;
  Future<void> _writes = Future.value();
  Object? _writeError;
  ReportsController({
    required this.reports,
    ReportFileGateway? files,
    ReportRewriter? rewriter,
    DateTime Function()? clock,
  }) : files = files ?? DesktopReportFileGateway(),
       rewriter = rewriter ?? ReportRewriter(),
       _clock = clock ?? DateTime.now {
    week = DateRange.weekOf(_clock());
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void start() {
    if (_started) return;
    _started = true;
    _history = reports.watchHistory().listen(
      (value) {
        history = value;
        _notify();
      },
      onError: (Object e) {
        error = '历史读取失败：$e';
        _notify();
      },
    );
    _run(() async {
      style = await reports.activeStyle();
    });
  }

  Future<void> _run(
    Future<void> Function() operation, {
    String failure = '操作失败',
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    notice = null;
    _notify();
    try {
      await operation();
    } catch (e) {
      error = '$failure：$e';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _queue(WeeklyReport snapshot) {
    final write = _writes.then((_) async {
      await reports.save(snapshot);
      _writeError = null;
    });
    _writes = write.catchError((Object e) {
      _writeError = e;
      error = '保存失败：$e';
      _notify();
    });
    return write;
  }

  void edit(WeeklyReport next) {
    if (busy || next.id != draft?.id) return;
    draft = next.copyWith(
      status: ReportStatus.draft,
      updatedAt: _clock().toUtc(),
    );
    _queue(draft!);
    _notify();
  }

  Future<void> _saveNow() async {
    final current = draft;
    if (current == null) return;
    await _queue(current);
    await _writes;
    if (_writeError != null) throw StateError('草稿未保存');
  }

  Future<void> generate() => _run(() async {
    await _saveNow();
    final next = await WeeklyReportBuilder(
      reports: reports,
      clock: _clock,
    ).build(week, style);
    await _queue(next);
    draft = next;
    notice = '草稿已生成并保存';
  }, failure: '生成失败');
  Future<void> save({bool finalize = false}) => _run(() async {
    if (draft == null) return;
    final next = draft!.copyWith(
      status: finalize ? ReportStatus.finalized : draft!.status,
    );
    await _queue(next);
    draft = next;
    notice = finalize ? '周报已归档' : '草稿已保存';
  }, failure: '保存失败');
  Future<void> selectWeek(DateTime date) => _run(() async {
    await _saveNow();
    week = DateRange.weekOf(date);
    draft = null;
  });
  Future<void> open(String id) => _run(() async {
    await _saveNow();
    final saved = await reports.get(id);
    if (saved == null) throw ArgumentError('报告不存在');
    draft = saved;
    week = saved.week;
  });
  String get preview => draft == null
      ? ''
      : PlainTextReportRenderer().render(draft!, draft!.style);
  void addNextAction(String text) {
    if (draft == null || busy || text.trim().isEmpty) return;
    final id = const Uuid().v4();
    final value = text.trim();
    edit(
      draft!.copyWith(
        nextWeekItems: [
          ...draft!.nextWeekItems,
          ReportItem(
            id: id,
            text: value,
            evidence: [
              ReportEvidenceRef(
                id: 'manual-$id',
                kind: 'manual',
                sourceId: draft!.id,
                title: '手动下周行动',
                detail: value,
                occurredAt: _clock().toUtc(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _validateContent(WeeklyReport report) {
    if ([
      ...report.workItems,
      ...report.nextWeekItems,
    ].any((i) => i.text.trim().isEmpty)) {
      throw ArgumentError('报告条目内容不能为空');
    }
  }

  Future<void> export(ReportExportFormat format) => _run(() async {
    await _saveNow();
    final report = draft;
    if (report == null) return;
    _validateContent(report);
    final Uint8List bytes = format == ReportExportFormat.xlsx
        ? await XlsxReportRenderer().render(report, report.style)
        : Uint8List.fromList(
            utf8.encode(MarkdownReportRenderer().render(report, report.style)),
          );
    final extension = format == ReportExportFormat.xlsx ? 'xlsx' : 'md';
    final saved = await files.save(
      filename: '工作周报-${reportDate(report.week.start)}.$extension',
      bytes: bytes,
    );
    notice = saved ? '周报已导出' : '已取消导出，草稿已保存';
  }, failure: '导出失败');
  Future<void> copy() => _run(() async {
    await _saveNow();
    if (draft != null) _validateContent(draft!);
    await files.copyPlainText(preview);
    notice = '纯文本已复制';
  }, failure: '复制失败');
  Future<void> rewrite() => _run(() async {
    await _saveNow();
    if (draft == null) return;
    final next = await rewriter.rewrite(draft!, draft!.style);
    await _queue(next);
    draft = next;
    notice = rewriter.lastWarning ?? '措辞已更新，事实依据保持一致';
  });
  Future<void> importStyle() => _run(() async {
    final sample = await files.pickStyleSample();
    if (sample == null) return;
    style = await ReportStyleService(reports)
        .importSample(filename: sample.filename, bytes: sample.bytes);
    notice = '样式已导入，生成新报告时使用';
  }, failure: '导入失败');
  Future<void> editStyle(ReportStyleProfile next) async {
    await reports.saveStyle(next);
    style = next;
    _notify();
  }

  void applyStyle() {
    if (draft != null) edit(draft!.copyWith(style: style));
  }

  @override
  void dispose() {
    _disposed = true;
    _history?.cancel();
    super.dispose();
  }
}
