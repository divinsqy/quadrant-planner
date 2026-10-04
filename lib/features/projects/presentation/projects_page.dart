import 'package:flutter/material.dart';

import '../../../domain/projects/project.dart';
import '../../../domain/projects/project_progress.dart';
import '../../../domain/tasks/task.dart';
import '../../tasks/data/task_repository.dart';
import '../data/project_repository.dart';
import 'project_editor_dialog.dart';

class ProjectsPage extends StatefulWidget {
  final ProjectRepository projects;
  final TaskRepository tasks;
  final ValueChanged<String> onOpenProject;

  const ProjectsPage({
    super.key,
    required this.projects,
    required this.tasks,
    required this.onOpenProject,
  });

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late Stream<List<Project>> _projectStream;
  late Stream<List<Task>> _taskStream;

  @override
  void initState() {
    super.initState();
    _setStreams();
  }

  @override
  void didUpdateWidget(ProjectsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projects != widget.projects ||
        oldWidget.tasks != widget.tasks) {
      _setStreams();
    }
  }

  void _setStreams() {
    _projectStream = widget.projects.watchAll();
    _taskStream = widget.tasks.watchTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('项目'),
        actions: [
          TextButton.icon(
            onPressed: () => showProjectEditor(
              context,
              onSave: (name, objective, deadline) async {
                await widget.projects.createProject(
                  name: name,
                  objective: objective,
                  deadline: deadline,
                );
              },
            ),
            icon: const Icon(Icons.add),
            label: const Text('新建项目'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Project>>(
        stream: _projectStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('加载项目失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = snapshot.data!;
          if (projects.isEmpty) {
            return const Center(child: Text('暂无项目，创建一个目标开始规划'));
          }
          return StreamBuilder<List<Task>>(
            stream: _taskStream,
            builder: (context, taskSnapshot) {
              final tasks = taskSnapshot.data ?? const <Task>[];
              return Column(
                children: [
                  if (taskSnapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('加载任务失败：${taskSnapshot.error}'),
                    ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: projects.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        final owned = tasks
                            .where((task) => task.projectId == project.id)
                            .toList(growable: false);
                        final progress = calculateProjectProgress(owned);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          title: Text(project.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (project.objective.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(project.objective),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '${owned.length} 项任务 · ${progress.toStringAsFixed(1)}%${project.deadline == null ? '' : ' · 截止 ${projectDateLabel(project.deadline!)}'}',
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progress / 100,
                                semanticsLabel: '${project.name} 项目进度',
                                semanticsValue:
                                    '${progress.toStringAsFixed(1)}%',
                              ),
                            ],
                          ),
                          onTap: () => widget.onOpenProject(project.id),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
