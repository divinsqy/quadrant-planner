import 'package:flutter/material.dart';

import '../../../domain/tasks/task_status.dart';
import '../../tasks/data/task_repository.dart';

class QuickCapture extends StatefulWidget {
  final TaskRepository taskRepository;
  final VoidCallback? onCreated;

  const QuickCapture({
    super.key,
    required this.taskRepository,
    this.onCreated,
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
        TaskDraft(
          title: title,
          status: TaskStatus.inbox,
        ),
      );
      _controller.clear();
      widget.onCreated?.call();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
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
  }
}
