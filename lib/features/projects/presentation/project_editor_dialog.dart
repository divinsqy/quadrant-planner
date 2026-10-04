import 'package:flutter/material.dart';

import '../../../domain/projects/milestone.dart';
import '../../../domain/projects/project.dart';

String projectDateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

Future<void> showProjectEditor(
  BuildContext context, {
  Project? project,
  required Future<void> Function(
    String name,
    String objective,
    DateTime? deadline,
  )
  onSave,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ProjectEditorDialog(
      title: project == null ? '新建项目' : '编辑项目',
      fieldPrefix: 'project',
      name: project?.name ?? '',
      objective: project?.objective ?? '',
      deadline: project?.deadline,
      onSave: onSave,
    ),
  );
}

Future<void> showMilestoneEditor(
  BuildContext context, {
  Milestone? milestone,
  required Future<void> Function(String name, DateTime? deadline) onSave,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ProjectEditorDialog(
      title: milestone == null ? '新建里程碑' : '编辑里程碑',
      fieldPrefix: 'milestone',
      name: milestone?.name ?? '',
      deadline: milestone?.deadline,
      onSave: (name, _, deadline) => onSave(name, deadline),
    ),
  );
}

class _ProjectEditorDialog extends StatefulWidget {
  final String title;
  final String fieldPrefix;
  final String name;
  final String? objective;
  final DateTime? deadline;
  final Future<void> Function(String, String, DateTime?) onSave;

  const _ProjectEditorDialog({
    required this.title,
    required this.fieldPrefix,
    required this.name,
    this.objective,
    this.deadline,
    required this.onSave,
  });

  @override
  State<_ProjectEditorDialog> createState() => _ProjectEditorDialogState();
}

class _ProjectEditorDialogState extends State<_ProjectEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late final _objective = TextEditingController(text: widget.objective ?? '');
  late final _deadline = TextEditingController(
    text: widget.deadline == null ? '' : projectDateLabel(widget.deadline!),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _objective.dispose();
    _deadline.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String text) {
    final clean = text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) {
      return null;
    }
    final date = DateTime.tryParse(clean);
    return date != null && projectDateLabel(date) == clean ? date : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        _name.text.trim(),
        _objective.text,
        _parseDate(_deadline.text),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _chooseDate() async {
    final initial = _parseDate(_deadline.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date != null && mounted) {
      _deadline.text = projectDateLabel(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: Key('${widget.fieldPrefix}-name'),
                controller: _name,
                autofocus: true,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: '名称'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入名称' : null,
              ),
              if (widget.objective != null) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: Key('${widget.fieldPrefix}-objective'),
                  controller: _objective,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '项目目标'),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: Key('${widget.fieldPrefix}-deadline'),
                controller: _deadline,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: '截止日期（可选）',
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: IconButton(
                    tooltip: '选择日期',
                    onPressed: _saving ? null : _chooseDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        _parseDate(value) != null
                    ? null
                    : '请输入有效日期 YYYY-MM-DD',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}
