import 'package:flutter/material.dart';

import '../../../domain/reports/weekly_report.dart';
import '../data/weekly_note_repository.dart';

Future<WeeklyNote?> showWeeklyNoteDialog(
  BuildContext context, {
  required WeeklyNoteRepository notes,
  required DateTime weekStart,
  String? taskId,
}) => showDialog<WeeklyNote>(
  context: context,
  builder: (_) =>
      WeeklyNoteDialog(notes: notes, weekStart: weekStart, taskId: taskId),
);

class WeeklyNoteDialog extends StatefulWidget {
  final WeeklyNoteRepository notes;
  final DateTime weekStart;
  final String? taskId;
  const WeeklyNoteDialog({
    super.key,
    required this.notes,
    required this.weekStart,
    this.taskId,
  });
  @override
  State<WeeklyNoteDialog> createState() => _WeeklyNoteDialogState();
}

class _WeeklyNoteDialogState extends State<WeeklyNoteDialog> {
  String problem = '', cause = '', solution = '', learning = '';
  bool busy = false;
  String? error;
  Future<void> _save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final note = await widget.notes.add(
        taskId: widget.taskId,
        weekStart: widget.weekStart,
        problem: problem,
        cause: cause,
        solution: solution,
        learning: learning,
      );
      if (mounted) Navigator.of(context).pop(note);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('记录本周笔记'),
    scrollable: true,
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('所属周：${reportDate(DateRange.weekOf(widget.weekStart).start)}'),
          TextFormField(
            decoration: const InputDecoration(labelText: '问题 / 困难'),
            maxLines: null,
            enabled: !busy,
            onChanged: (v) => problem = v,
          ),
          TextFormField(
            decoration: const InputDecoration(labelText: '原因'),
            maxLines: null,
            enabled: !busy,
            onChanged: (v) => cause = v,
          ),
          TextFormField(
            decoration: const InputDecoration(labelText: '解决 / 进展'),
            maxLines: null,
            enabled: !busy,
            onChanged: (v) => solution = v,
          ),
          TextFormField(
            decoration: const InputDecoration(labelText: '体会 / 感受'),
            maxLines: null,
            enabled: !busy,
            onChanged: (v) => learning = v,
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: busy ? null : _save, child: const Text('保存笔记')),
    ],
  );
}
