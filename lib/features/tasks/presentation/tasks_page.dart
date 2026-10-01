import 'package:flutter/material.dart';

import '../../../domain/tasks/task.dart';
import '../application/task_editor_controller.dart';
import '../data/task_activity_repository.dart';
import '../data/task_repository.dart';
import 'task_preview_drawer.dart';

class TasksPage extends StatefulWidget {
  final TaskRepository tasks;
  final TaskEditorController editor;
  final TaskActivityRepository activity;
  final ValueChanged<String>? onOpenTask;

  const TasksPage({
    super.key,
    required this.tasks,
    required this.editor,
    required this.activity,
    this.onOpenTask,
  });

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String? _selectedTaskId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
      stream: widget.tasks.watchTasks(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Task>[];
        Task? selected;
        for (final task in items) {
          if (task.id == _selectedTaskId) {
            selected = task;
            break;
          }
        }

        return Scaffold(
          appBar: AppBar(title: const Text('任务')),
          body: Row(
            children: [
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('暂无任务'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final task = items[index];
                          return ListTile(
                            selected: task.id == _selectedTaskId,
                            title: Text(task.title),
                            subtitle: Text(
                              '${task.status.name} · '
                              '重要性 ${task.importance} · '
                              '基础紧急性 ${task.baseUrgency}',
                            ),
                            onTap: () =>
                                setState(() => _selectedTaskId = task.id),
                            onLongPress: widget.onOpenTask == null
                                ? null
                                : () => widget.onOpenTask!(task.id),
                          );
                        },
                      ),
              ),
              if (selected != null) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 360,
                  child: TaskPreviewDrawer(
                    task: selected,
                    controller: widget.editor,
                    onClose: () => setState(() => _selectedTaskId = null),
                    onOpenDetail: widget.onOpenTask == null
                        ? null
                        : () => widget.onOpenTask!(selected!.id),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
