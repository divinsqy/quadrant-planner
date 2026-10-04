import 'package:flutter/material.dart';

import '../../../domain/reports/report_style_profile.dart';
import '../../../domain/reports/weekly_report.dart';
import '../application/reports_controller.dart';
import 'report_editor.dart';
import 'weekly_note_dialog.dart';

class ReportsPage extends StatefulWidget {
  final ReportsController controller;
  final ValueChanged<String>? onOpenTask;
  const ReportsPage({super.key, required this.controller, this.onOpenTask});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportsController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.start();
  }

  Future<void> _date() async {
    final date = await showDatePicker(
      context: context,
      initialDate: c.week.start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) await c.selectWeek(date);
  }

  void _preview() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('周报预览'),
      scrollable: true,
      content: SizedBox(
        width: 720,
        height: 400,
        child: SingleChildScrollView(
          child: SelectableText(
            c.preview,
            key: const ValueKey('report-preview'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  Future<void> _style() async {
    var next = c.style;
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          Widget field(
            String label,
            String value,
            ReportStyleProfile Function(String) change,
          ) => TextFormField(
            initialValue: value,
            decoration: InputDecoration(labelText: label),
            enabled: !busy,
            onChanged: (v) => next = change(v),
          );
          return AlertDialog(
            title: const Text('编辑周报样式'),
            scrollable: true,
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field('样式名称', next.name, (v) => next.copyWith(name: v)),
                  field('报告标题', next.title, (v) => next.copyWith(title: v)),
                  field(
                    '姓名标签',
                    next.authorLabel,
                    (v) => next.copyWith(authorLabel: v),
                  ),
                  field(
                    '日期标签',
                    next.dateLabel,
                    (v) => next.copyWith(dateLabel: v),
                  ),
                  field(
                    '工作内容标题',
                    next.workHeading,
                    (v) => next.copyWith(workHeading: v),
                  ),
                  field(
                    'Q/A 标题',
                    next.reflectionHeading,
                    (v) => next.copyWith(reflectionHeading: v),
                  ),
                  field(
                    '下周计划标题',
                    next.nextWeekHeading,
                    (v) => next.copyWith(nextWeekHeading: v),
                  ),
                  field(
                    '主管反馈标题',
                    next.feedbackHeading,
                    (v) => next.copyWith(feedbackHeading: v),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: next.numbering,
                    decoration: const InputDecoration(labelText: '编号分隔符'),
                    items: [
                      for (final value in ['.', '、', ')'])
                        DropdownMenuItem(
                          value: value,
                          child: Text('1$value 工作事项'),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) =>
                              update(() => next = next.copyWith(numbering: v)),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('导出时显示项目标题'),
                    value: next.projectHeadings,
                    onChanged: busy
                        ? null
                        : (v) => update(
                            () => next = next.copyWith(
                              projectHeadings: v ?? false,
                            ),
                          ),
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        update(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await c.editStyle(next);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        } catch (e) {
                          if (ctx.mounted) {
                            update(() {
                              busy = false;
                              error = '$e';
                            });
                          }
                        }
                      },
                child: const Text('保存样式'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _nextAction() async {
    var text = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('添加下周行动'),
          content: TextFormField(
            decoration: const InputDecoration(labelText: '下周行动'),
            maxLines: null,
            onChanged: (v) => update(() => text = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: text.trim().isEmpty
                  ? null
                  : () {
                      c.addNextAction(text);
                      Navigator.of(ctx).pop();
                    },
              child: const Text('保存行动'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('周报')),
    body: AnimatedBuilder(
      animation: c,
      builder: (context, _) => ListView(
        key: const PageStorageKey('reports-workspace'),
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: '上一周',
                onPressed: c.busy
                    ? null
                    : () => c.selectWeek(
                        DateTime(
                          c.week.start.year,
                          c.week.start.month,
                          c.week.start.day - 7,
                        ),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: c.busy ? null : _date,
                child: Text(
                  '${reportDate(c.week.start)} ～ ${reportDate(c.week.end)}',
                ),
              ),
              IconButton(
                tooltip: '下一周',
                onPressed: c.busy
                    ? null
                    : () => c.selectWeek(
                        DateTime(
                          c.week.start.year,
                          c.week.start.month,
                          c.week.start.day + 7,
                        ),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
              FilledButton(
                onPressed: c.busy ? null : c.generate,
                child: Text(c.draft == null ? '生成草稿' : '重新生成草稿'),
              ),
              OutlinedButton(
                onPressed: c.busy ? null : c.importStyle,
                child: const Text('导入样式'),
              ),
              TextButton(
                onPressed: c.busy ? null : _style,
                child: const Text('编辑样式'),
              ),
              Tooltip(
                message: '记录本周笔记',
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('记录本周笔记'),
                  onPressed: c.busy
                      ? null
                      : () => showWeeklyNoteDialog(
                          context,
                          notes: c.reports.notes,
                          weekStart: c.week.start,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('当前样式：${c.style.name}'),
          if (c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (c.notice != null) Text(c.notice!),
          if (c.busy) const LinearProgressIndicator(),
          if (c.draft != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: c.busy ? null : _preview,
                  child: const Text('预览'),
                ),
                TextButton(
                  onPressed: c.busy ? null : () => c.save(),
                  child: const Text('保存草稿'),
                ),
                TextButton(
                  onPressed: c.busy ? null : () => c.save(finalize: true),
                  child: const Text('归档周报'),
                ),
                TextButton(
                  onPressed: c.busy ? null : c.applyStyle,
                  child: const Text('应用当前样式'),
                ),
                TextButton(
                  onPressed: c.busy || !c.rewriter.available ? null : c.rewrite,
                  child: Text(c.rewriter.available ? 'AI 改写' : 'AI 改写（未配置）'),
                ),
                OutlinedButton(
                  onPressed: c.busy
                      ? null
                      : () => c.export(ReportExportFormat.markdown),
                  child: const Text('导出 Markdown'),
                ),
                OutlinedButton(
                  onPressed: c.busy
                      ? null
                      : () => c.export(ReportExportFormat.xlsx),
                  child: const Text('导出 XLSX'),
                ),
                OutlinedButton(
                  onPressed: c.busy ? null : c.copy,
                  child: const Text('复制纯文本'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ReportEditor(
              key: ValueKey(c.draft!.id),
              report: c.draft!,
              enabled: !c.busy,
              onChanged: c.edit,
              onOpenTask: widget.onOpenTask,
              onAddNextAction: _nextAction,
            ),
          ],
          const SizedBox(height: 32),
          Text('历史周报', style: Theme.of(context).textTheme.titleLarge),
          if (c.history.isEmpty) const Text('生成并保存报告后，将在这里显示历史。'),
          for (final report in c.history)
            ListTile(
              key: ValueKey('report-history-${report.id}'),
              title: Text(
                '${reportDate(report.week.start)} ～ ${reportDate(report.week.end)}',
              ),
              subtitle: Text(
                '${report.status == ReportStatus.finalized ? '已归档' : '草稿'} · ${report.author} · ${report.workItems.length} 项工作',
              ),
              onTap: c.busy ? null : () => c.open(report.id),
            ),
        ],
      ),
    ),
  );
}
