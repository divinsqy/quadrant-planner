import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/tasks/task_status.dart';
import '../../tasks/data/task_repository.dart';

class QuickCapture extends StatefulWidget {
  final TaskRepository taskRepository;
  final VoidCallback? onCreated;
  final bool autofocus;

  const QuickCapture({
    super.key,
    required this.taskRepository,
    this.onCreated,
    this.autofocus = false,
  });

  @override
  State<QuickCapture> createState() => _QuickCaptureState();
}

class _QuickCaptureState extends State<QuickCapture> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入任务标题');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      await widget.taskRepository.createTask(
        TaskDraft(title: title, status: TaskStatus.inbox),
      );
      _controller.clear();
      widget.onCreated?.call();
    } catch (error) {
      if (mounted) setState(() => _error = '记录失败：$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capture = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: widget.autofocus,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '快速记录一个待办...',
              errorText: _error,
              prefixIcon: const Icon(Icons.add_task_rounded),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: const Icon(Icons.add_rounded),
          label: const Text('快速记录'),
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
      },
      child: Focus(child: capture),
    );
  }
}
