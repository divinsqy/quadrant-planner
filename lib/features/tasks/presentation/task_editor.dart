import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/projects/project.dart';
import '../../../domain/projects/milestone.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../../domain/tasks/workload.dart';
import '../../projects/data/project_repository.dart';
import '../application/task_editor_controller.dart';

class TaskEditor extends StatefulWidget {
  final Task task;
  final TaskEditorController controller;
  final ProjectRepository? projects;
  final ValueChanged<Task>? onSaved;
  final bool compact;
  final TaskStatus? initialStatus;

  const TaskEditor({
    super.key,
    required this.task,
    required this.controller,
    this.projects,
    this.onSaved,
    this.compact = false,
    this.initialStatus,
  });
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final TextEditingController _title = TextEditingController();
  late final TextEditingController _description = TextEditingController();
  late final TextEditingController _deadline = TextEditingController();
  late final TextEditingController _estimate = TextEditingController();
  late final TextEditingController _progress = TextEditingController();
  late int _importance;
  late int _urgency;
  late TaskStatus _status;
  late Workload _workload;
  late bool _includeReport;
  String? _projectId;
  String? _milestoneId;
  late Task _baseline;
  bool _projectEdited = false;
  bool _milestoneEdited = false;
  String? _error;
  bool _saving = false;
  late Stream<List<Project>>? _projects;
  Stream<List<Milestone>>? _milestones;

  @override
  void initState() {
    super.initState();
    _projects = widget.projects?.watchAll();
    _load(widget.task);
    _status = widget.initialStatus ?? _status;
  }

  void _load(Task task) {
    _baseline = task;
    _projectEdited = false;
    _milestoneEdited = false;
    _title.text = task.title;
    _description.text = task.description;
    _deadline.text = _formatDate(task.deadline);
    _estimate.text = task.estimatedMinutes?.toString() ?? '';
    _progress.text = task.progress.toString();
    _importance = task.importance;
    _urgency = task.baseUrgency;
    _status = task.status;
    _workload = task.workload;
    _includeReport = task.includeInWeeklyReport;
    _projectId = task.projectId;
    _milestoneId = task.milestoneId;
    _milestones = _projectId == null
        ? null
        : widget.projects?.watchMilestones(_projectId!);
    _error = null;
  }

  String _formatDate(DateTime? value) {
    final date = value?.toLocal();
    return date == null
        ? ''
        : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void didUpdateWidget(covariant TaskEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projects != widget.projects) {
      _projects = widget.projects?.watchAll();
    }
    if (oldWidget.task.id != widget.task.id) _load(widget.task);
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _description,
      _deadline,
      _estimate,
      _progress,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    DateTime? deadline;
    int? estimate;
    final progress = int.tryParse(_progress.text.trim());
    try {
      if (_title.text.trim().isEmpty) throw ArgumentError('任务标题不能为空');
      if (_deadline.text.trim().isNotEmpty) {
        final input = _deadline.text.trim();
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
          throw ArgumentError('截止日期格式为 YYYY-MM-DD');
        }
        final parts = input.split('-').map(int.parse).toList();
        deadline = DateTime(parts[0], parts[1], parts[2]);
        if (deadline.year != parts[0] ||
            deadline.month != parts[1] ||
            deadline.day != parts[2]) {
          throw ArgumentError('截止日期无效');
        }
      }
      if (_estimate.text.trim().isNotEmpty) {
        estimate = int.tryParse(_estimate.text.trim());
        if (estimate == null || estimate <= 0) {
          throw ArgumentError('预计时长必须为正整数');
        }
      }
      if (progress == null || progress < 0 || progress > 100) {
        throw ArgumentError('完成进度必须为 0–100');
      }
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.controller.save(
        widget.task,
        title: _title.text.trim() == _baseline.title
            ? null
            : _title.text.trim(),
        description: _description.text.trim() == _baseline.description
            ? null
            : _description.text.trim(),
        status: _status == _baseline.status ? null : _status,
        importance: _importance == _baseline.importance ? null : _importance,
        baseUrgency: _urgency == _baseline.baseUrgency ? null : _urgency,
        deadline: _deadline.text.trim() == _formatDate(_baseline.deadline)
            ? unchangedTaskField
            : deadline,
        estimatedMinutes: estimate == _baseline.estimatedMinutes
            ? unchangedTaskField
            : estimate,
        workload: _workload == _baseline.workload ? null : _workload,
        progress: progress == _baseline.progress ? null : progress,
        includeInWeeklyReport: _includeReport == _baseline.includeInWeeklyReport
            ? null
            : _includeReport,
        projectId: _projectEdited ? _projectId : unchangedTaskField,
        milestoneId: _milestoneEdited ? _milestoneId : unchangedTaskField,
      );
      if (!mounted) return;
      setState(() => _load(saved));
      widget.onSaved?.call(saved);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = widget.compact ? 10.0 : 16.0;
    final editor = ListView(
      shrinkWrap: true,
      primary: false,
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
          isExpanded: true,
          decoration: const InputDecoration(labelText: '状态'),
          items: [
            for (final status in TaskStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(taskStatusLabel(status)),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _status = value);
          },
        ),
        if (_projects != null) ...[
          SizedBox(height: spacing),
          StreamBuilder<List<Project>>(
            stream: _projects,
            builder: (context, snapshot) {
              final projects = snapshot.data ?? const <Project>[];
              return DropdownButtonFormField<String>(
                key: ValueKey('project-$_projectId'),
                initialValue: _projectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '项目'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('无项目')),
                  for (final project in projects)
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(project.name),
                    ),
                  if (_projectId != null &&
                      !projects.any((p) => p.id == _projectId))
                    DropdownMenuItem(
                      value: _projectId,
                      child: const Text('当前项目'),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _projectId = value == '' ? null : value;
                  _projectEdited = true;
                  _milestoneEdited = true;
                  _milestoneId = null;
                  _milestones = _projectId == null
                      ? null
                      : widget.projects?.watchMilestones(_projectId!);
                }),
              );
            },
          ),
          if (_projectId != null) ...[
            SizedBox(height: spacing),
            StreamBuilder<List<Milestone>>(
              stream: _milestones,
              builder: (context, snapshot) {
                final milestones = snapshot.data ?? const <Milestone>[];
                return DropdownButtonFormField<String>(
                  key: ValueKey('milestone-$_projectId-$_milestoneId'),
                  initialValue: _milestoneId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '里程碑'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('无里程碑')),
                    for (final milestone in milestones)
                      DropdownMenuItem(
                        value: milestone.id,
                        child: Text(milestone.name),
                      ),
                    if (_milestoneId != null &&
                        !milestones.any((m) => m.id == _milestoneId))
                      DropdownMenuItem(
                        value: _milestoneId,
                        child: const Text('当前里程碑'),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _milestoneEdited = true;
                    _milestoneId = value == '' ? null : value;
                  }),
                );
              },
            ),
          ],
        ],
        SizedBox(height: spacing),
        Text('重要性 $_importance'),
        Semantics(
          label: '重要性',
          child: Slider(
            value: _importance.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$_importance',
            onChanged: (value) => setState(() => _importance = value.round()),
          ),
        ),
        Text('基础紧急性 $_urgency'),
        Semantics(
          label: '基础紧急性',
          child: Slider(
            value: _urgency.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$_urgency',
            onChanged: (value) => setState(() => _urgency = value.round()),
          ),
        ),
        SizedBox(height: spacing),
        TextField(
          controller: _deadline,
          decoration: const InputDecoration(
            labelText: '截止日期（YYYY-MM-DD）',
            hintText: '留空清除截止日期',
          ),
        ),
        SizedBox(height: spacing),
        TextField(
          controller: _estimate,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '预计时长（分钟）',
            hintText: '留空表示未设置',
          ),
        ),
        SizedBox(height: spacing),
        DropdownButtonFormField<Workload>(
          initialValue: _workload,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '工作量'),
          items: [
            for (final workload in Workload.values)
              DropdownMenuItem(
                value: workload,
                child: Text(switch (workload) {
                  Workload.small => '小',
                  Workload.medium => '中',
                  Workload.large => '大',
                }),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _workload = value);
          },
        ),
        SizedBox(height: spacing),
        TextField(
          controller: _progress,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '完成进度（0–100）'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('计入周报'),
          value: _includeReport,
          onChanged: (value) => setState(() => _includeReport = value ?? false),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      },
      child: Focus(child: editor),
    );
  }
}

String taskStatusLabel(TaskStatus status) => switch (status) {
  TaskStatus.inbox => '收集箱',
  TaskStatus.planned => '已规划',
  TaskStatus.inProgress => '进行中',
  TaskStatus.waiting => '等待中',
  TaskStatus.completed => '已完成',
  TaskStatus.cancelled => '已取消',
};
