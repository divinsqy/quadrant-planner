import 'package:flutter/material.dart';

import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../projects/data/project_repository.dart';
import '../../tasks/application/task_editor_controller.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/presentation/task_editor.dart';

class InboxPage extends StatefulWidget {
  final TaskRepository tasks;
  final TaskEditorController editor;
  final ValueChanged<String>? onOpenTask;
  final ProjectRepository? projects;

  const InboxPage({
    super.key,
    required this.tasks,
    required this.editor,
    this.onOpenTask,
    this.projects,
  });
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  late final _items = widget.tasks.watchTasks(
    statuses: const {TaskStatus.inbox},
  );
  final _busy = <String>{};

  Future<void> _plan(Task task) async {
    if (_busy.contains(task.id)) return;
    setState(() => _busy.add(task.id));
    try {
      await widget.editor.save(task, status: TaskStatus.planned);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('规划失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(task.id));
    }
  }

  Future<void> _planAndEdit(Task task) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: TaskEditor(
            task: task,
            initialStatus: TaskStatus.planned,
            controller: widget.editor,
            projects: widget.projects,
            onSaved: (_) => Navigator.pop(context),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Task>>(
    stream: _items,
    builder: (context, snapshot) {
      final items = snapshot.data ?? const <Task>[];
      return Scaffold(
        appBar: AppBar(title: const Text('收集箱')),
        body: snapshot.hasError
            ? Center(child: Text('读取失败：${snapshot.error}'))
            : items.isEmpty
            ? const Center(child: Text('收集箱为空'))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final task = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(task.title),
                          subtitle: task.description.trim().isEmpty
                              ? null
                              : Text(task.description),
                          onTap: widget.onOpenTask == null
                              ? () => _planAndEdit(task)
                              : () => widget.onOpenTask!(task.id),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: _busy.contains(task.id)
                                  ? null
                                  : () => _plan(task),
                              child: const Text('规划'),
                            ),
                            OutlinedButton(
                              onPressed: _busy.contains(task.id)
                                  ? null
                                  : () => _planAndEdit(task),
                              child: const Text('规划并编辑'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      );
    },
  );
}
