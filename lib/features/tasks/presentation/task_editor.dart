import 'package:flutter/material.dart';

import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../application/task_editor_controller.dart';

class TaskEditor extends StatefulWidget {
  final Task task;
  final TaskEditorController controller;
  final ValueChanged<Task>? onSaved;
  final bool compact;

  const TaskEditor({
    super.key,
    required this.task,
    required this.controller,
    this.onSaved,
    this.compact = false,
  });

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.task.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.task.description);
  late int _importance = widget.task.importance;
  late int _urgency = widget.task.baseUrgency;
  late TaskStatus _status = widget.task.status;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant TaskEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _title.text = widget.task.title;
      _description.text = widget.task.description;
      _importance = widget.task.importance;
      _urgency = widget.task.baseUrgency;
      _status = widget.task.status;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.save(
        widget.task,
        title: _title.text.trim(),
        description: _description.text.trim(),
        status: _status,
        importance: _importance,
        baseUrgency: _urgency,
      );
      widget.onSaved?.call(saved);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = widget.compact ? 10.0 : 16.0;
    return ListView(
      shrinkWrap: true,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: '任务标题'),
        ),
        SizedBox(height: spacing),
        TextField(
          controller: _description,
          minLines: widget.compact ? 2 : 3,
          maxLines: widget.compact ? 4 : 7,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        SizedBox(height: spacing),
        DropdownButtonFormField<TaskStatus>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: '状态'),
          items: [
            for (final status in TaskStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(_statusLabel(status)),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _status = value);
          },
        ),
        SizedBox(height: spacing),
        Text('重要性 $_importance'),
        Slider(
          value: _importance.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          onChanged: (value) => setState(() => _importance = value.round()),
        ),
        Text('基础紧急性 $_urgency'),
        Slider(
          value: _urgency.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          onChanged: (value) => setState(() => _urgency = value.round()),
        ),
        SizedBox(height: spacing),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ),
      ],
    );
  }

  String _statusLabel(TaskStatus status) {
    return switch (status) {
      TaskStatus.inbox => '收集箱',
      TaskStatus.planned => '已规划',
      TaskStatus.inProgress => '进行中',
      TaskStatus.waiting => '等待中',
      TaskStatus.completed => '已完成',
      TaskStatus.cancelled => '已取消',
    };
  }
}
