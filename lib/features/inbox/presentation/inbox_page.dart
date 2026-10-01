import 'package:flutter/material.dart';

import '../../../domain/tasks/task_status.dart';
import '../../tasks/application/task_editor_controller.dart';
import '../../tasks/data/task_repository.dart';

class InboxPage extends StatelessWidget {
  final TaskRepository tasks;
  final TaskEditorController editor;
  final ValueChanged<String>? onOpenTask;

  const InboxPage({
    super.key,
    required this.tasks,
    required this.editor,
    this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: tasks.watchTasks(statuses: const {TaskStatus.inbox}),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        return Scaffold(
          appBar: AppBar(title: const Text('收集箱')),
          body: items.isEmpty
              ? const Center(child: Text('收集箱为空'))
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final task = items[index];
                    return ListTile(
                      title: Text(task.title),
                      subtitle: task.description.trim().isEmpty
                          ? null
                          : Text(
                              task.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: onOpenTask == null
                          ? null
                          : () => onOpenTask!(task.id),
                      trailing: TextButton(
                        onPressed: () => editor.save(
                          task,
                          status: TaskStatus.planned,
                        ),
                        child: const Text('规划'),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
