import 'package:flutter/material.dart';

import '../../../domain/reports/weekly_report.dart';
import 'evidence_panel.dart';

class ReportEditor extends StatelessWidget {
  final WeeklyReport report;
  final ValueChanged<WeeklyReport> onChanged;
  final ValueChanged<String>? onOpenTask;
  final bool enabled;
  final VoidCallback? onAddNextAction;
  const ReportEditor({
    super.key,
    required this.report,
    required this.onChanged,
    this.onOpenTask,
    this.enabled = true,
    this.onAddNextAction,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReportTextInput(
        value: report.author,
        label: report.style.authorLabel,
        enabled: enabled,
        onChanged: (value) => onChanged(report.copyWith(author: value)),
      ),
      const SizedBox(height: 16),
      Text(
        report.style.workHeading,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (report.workItems.isEmpty) const Text('本周尚无符合事实记录的工作事项，可以补充进度或周报笔记。'),
      for (var i = 0; i < report.workItems.length; i++) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ReportTextInput(
                  fieldKey: ValueKey('report-work-$i'),
                  value: report.workItems[i].text,
                  label: '${i + 1}. 工作结果',
                  enabled: enabled,
                  multiline: true,
                  onChanged: (value) {
                    final items = [...report.workItems];
                    items[i] = items[i].copyWith(text: value);
                    onChanged(report.copyWith(workItems: items));
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: ReportTextInput(
                  value: '${report.workItems[i].progress}',
                  label: '完成度%',
                  enabled: enabled,
                  onChanged: (value) {
                    final progress = int.tryParse(value);
                    if (progress == null || progress < 0 || progress > 100) {
                      return;
                    }
                    final items = [...report.workItems];
                    items[i] = items[i].copyWith(progress: progress);
                    onChanged(report.copyWith(workItems: items));
                  },
                ),
              ),
            ],
          ),
        ),
        EvidencePanel(
          evidence: report.workItems[i].evidence,
          storageId: '${report.id}-work-${report.workItems[i].id}',
          onOpenTask: onOpenTask,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '移除工作事项',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: enabled
                ? () => onChanged(
                    report.copyWith(
                      workItems: [...report.workItems]..removeAt(i),
                    ),
                  )
                : null,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        report.style.reflectionHeading,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (report.reflections.isEmpty) const Text('记录本周笔记后，将在这里显示 Q/A。'),
      for (var i = 0; i < report.reflections.length; i++) ...[
        ReportTextInput(
          value: report.reflections[i].question,
          label: 'Q${i + 1}',
          enabled: enabled,
          multiline: true,
          onChanged: (value) {
            final items = [...report.reflections];
            items[i] = items[i].copyWith(question: value);
            onChanged(report.copyWith(reflections: items));
          },
        ),
        ReportTextInput(
          value: report.reflections[i].answer,
          label: 'A${i + 1}',
          enabled: enabled,
          multiline: true,
          onChanged: (value) {
            final items = [...report.reflections];
            items[i] = items[i].copyWith(answer: value);
            onChanged(report.copyWith(reflections: items));
          },
        ),
        EvidencePanel(
          evidence: report.reflections[i].evidence,
          storageId: '${report.id}-qa-${report.reflections[i].id}',
          onOpenTask: onOpenTask,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '移除 Q/A',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: enabled
                ? () => onChanged(
                    report.copyWith(
                      reflections: [...report.reflections]..removeAt(i),
                    ),
                  )
                : null,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        report.style.nextWeekHeading,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: enabled ? onAddNextAction : null,
          icon: const Icon(Icons.add),
          label: const Text('添加下周行动'),
        ),
      ),
      for (var i = 0; i < report.nextWeekItems.length; i++) ...[
        ReportTextInput(
          value: report.nextWeekItems[i].text,
          label: '${i + 1}. 下周行动',
          enabled: enabled,
          multiline: true,
          onChanged: (value) {
            final items = [...report.nextWeekItems];
            items[i] = items[i].copyWith(text: value);
            onChanged(report.copyWith(nextWeekItems: items));
          },
        ),
        EvidencePanel(
          evidence: report.nextWeekItems[i].evidence,
          storageId: '${report.id}-next-${report.nextWeekItems[i].id}',
          onOpenTask: onOpenTask,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '移除下周行动',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: enabled
                ? () => onChanged(
                    report.copyWith(
                      nextWeekItems: [...report.nextWeekItems]..removeAt(i),
                    ),
                  )
                : null,
          ),
        ),
      ],
      const SizedBox(height: 16),
      ReportTextInput(
        value: report.supervisorFeedback,
        label: report.style.feedbackHeading,
        enabled: enabled,
        multiline: true,
        onChanged: (value) =>
            onChanged(report.copyWith(supervisorFeedback: value)),
      ),
    ],
  );
}

class ReportTextInput extends StatefulWidget {
  final String value;
  final String label;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;
  final bool enabled;
  final bool multiline;
  const ReportTextInput({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.fieldKey,
    this.enabled = true,
    this.multiline = false,
  });
  @override
  State<ReportTextInput> createState() => _ReportTextInputState();
}

class _ReportTextInputState extends State<ReportTextInput> {
  late final _text = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(ReportTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value) {
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      key: widget.fieldKey,
      controller: _text,
      enabled: widget.enabled,
      minLines: widget.multiline ? 1 : null,
      maxLines: widget.multiline ? null : 1,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: widget.onChanged,
    ),
  );
}
