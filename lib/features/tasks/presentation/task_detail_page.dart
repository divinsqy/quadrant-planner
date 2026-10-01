import 'package:flutter/material.dart';

import '../../../domain/tasks/task_activity_event.dart';
import '../application/task_editor_controller.dart';
import '../data/task_activity_repository.dart';
import '../data/task_repository.dart';
import 'task_editor.dart';

class TaskDetailPage extends StatelessWidget {
  final String taskId;
  final TaskRepository tasks;
  final TaskEditorController editor;
  final TaskActivityRepository activity;

  const TaskDetailPage({
    super.key,
    required this.taskId,
    required this.tasks,
    required this.editor,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: tasks.watchTask(taskId),
      builder: (context, snapshot) {
        final task = snapshot.data;
        if (task == null) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const Scaffold(
            body: Center(child: Text('任务不存在')),
          );
        }

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text(task.title),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Subtasks'),
                  Tab(text: 'Dependencies'),
                  Tab(text: 'Activity'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: TaskEditor(
                    task: task,
                    controller: editor,
                  ),
                ),
                const _EmptyTab(
                  icon: Icons.account_tree_outlined,
                  text: '暂无子任务',
                ),
                const _EmptyTab(
                  icon: Icons.link_rounded,
                  text: '暂无依赖关系',
                ),
                _ActivityTab(
                  taskId: task.id,
                  activity: activity,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityTab extends StatelessWidget {
  final String taskId;
  final TaskActivityRepository activity;

  const _ActivityTab({
    required this.taskId,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskActivityEvent>>(
      future: activity.fetchPage(taskId, limit: 50),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data!;
        if (events.isEmpty) {
          return const Center(child: Text('暂无活动记录'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: events.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(_eventLabel(event.type)),
              subtitle: Text(event.occurredAt.toLocal().toString()),
            );
          },
        );
      },
    );
  }

  String _eventLabel(String type) {
    return switch (type) {
      'completed' => '任务完成',
      'task_updated' => '任务更新',
      _ => type,
    };
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyTab({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(text),
        ],
      ),
    );
  }
}
