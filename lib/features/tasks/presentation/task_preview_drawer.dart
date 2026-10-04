import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../application/task_editor_controller.dart';
import '../../projects/data/project_repository.dart';
import 'task_editor.dart';

class TaskPreviewDrawer extends StatefulWidget {
  final Task task;
  final TaskEditorController controller;
  final VoidCallback? onClose;
  final VoidCallback? onOpenDetail;
  final ValueChanged<Task>? onTaskChanged;
  final ProjectRepository? projects;

  const TaskPreviewDrawer({
    super.key,
    required this.task,
    required this.controller,
    this.onClose,
    this.onOpenDetail,
    this.onTaskChanged,
    this.projects,
  });

  @override
  State<TaskPreviewDrawer> createState() => _TaskPreviewDrawerState();
}

class _TaskPreviewDrawerState extends State<TaskPreviewDrawer> {
  late Task _task = widget.task;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant TaskPreviewDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.updatedAt != widget.task.updatedAt) {
      _task = widget.task;
    }
  }

  Future<void> _changeStatus(TaskStatus status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = status == TaskStatus.completed
          ? await widget.controller.complete(_task)
          : await widget.controller.save(_task, status: status);
      if (!mounted) return;
      setState(() => _task = saved);
      widget.onTaskChanged?.call(saved);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: TaskEditor(
              task: _task,
              controller: widget.controller,
              projects: widget.projects,
              compact: true,
              onSaved: (saved) {
                if (mounted) {
                  setState(() => _task = saved);
                  widget.onTaskChanged?.call(saved);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final drawer = Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _task.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: '关闭',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel(_task.status),
              style: TextStyle(color: scheme.primary),
            ),
            const SizedBox(height: 16),
            if (_task.description.trim().isNotEmpty) ...[
              Text(_task.description),
              const SizedBox(height: 16),
            ],
            _Metric(label: '重要性', value: _task.importance.toString()),
            _Metric(label: '基础紧急性', value: _task.baseUrgency.toString()),
            _Metric(
              label: '预计时长',
              value: _task.estimatedMinutes == null
                  ? '未设置'
                  : '${_task.estimatedMinutes} min',
            ),
            _Metric(label: '完成进度', value: '${_task.progress}%'),
            _Metric(
              label: '截止日期',
              value: _task.deadline == null
                  ? '未设置'
                  : _task.deadline!.toLocal().toString().split(' ').first,
            ),
            TextButton.icon(
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('轻量编辑'),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_task.status == TaskStatus.planned)
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _changeStatus(TaskStatus.inProgress),
                    child: const Text('开始任务'),
                  ),
                if (_task.status != TaskStatus.waiting &&
                    _task.status != TaskStatus.completed)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _changeStatus(TaskStatus.waiting),
                    child: const Text('等待'),
                  ),
                if (_task.status != TaskStatus.completed)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _changeStatus(TaskStatus.completed),
                    child: const Text('标记完成'),
                  ),
              ],
            ),
            if (widget.onOpenDetail != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: widget.onOpenDetail,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('打开完整详情'),
              ),
            ],
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.onClose?.call(),
      },
      child: Focus(autofocus: true, child: drawer),
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
