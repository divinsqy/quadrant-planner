import 'package:flutter/material.dart';

import '../../../domain/projects/milestone.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../tasks/data/task_repository.dart';
import '../application/project_controller.dart';
import '../data/project_repository.dart';
import 'project_editor_dialog.dart';

class ProjectDetailPage extends StatefulWidget {
  final String projectId;
  final ProjectRepository projects;
  final TaskRepository tasks;
  final ValueChanged<String>? onOpenTask;
  final ValueChanged<String>? onShowQuadrant;

  const ProjectDetailPage({
    super.key,
    required this.projectId,
    required this.projects,
    required this.tasks,
    this.onOpenTask,
    this.onShowQuadrant,
  });

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late ProjectController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = ProjectController(
      projectId: widget.projectId,
      projects: widget.projects,
      tasks: widget.tasks,
    )..start();
  }

  @override
  void didUpdateWidget(ProjectDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.projects != widget.projects ||
        oldWidget.tasks != widget.tasks) {
      _controller.dispose();
      _createController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _editProject(ProjectState state) => showProjectEditor(
    context,
    project: state.project,
    onSave: (name, objective, deadline) async {
      await _controller.saveProject(
        name: name,
        objective: objective,
        deadline: deadline,
      );
    },
  );

  Future<void> _editMilestone(Milestone? milestone) => showMilestoneEditor(
    context,
    milestone: milestone,
    onSave: (name, deadline) async {
      if (milestone == null) {
        await _controller.createMilestone(name: name, deadline: deadline);
      } else {
        await _controller.saveMilestone(
          milestone,
          name: name,
          deadline: deadline,
        );
      }
    },
  );

  Future<void> _completeMilestone(Milestone milestone, bool completed) async {
    try {
      await _controller.setMilestoneCompleted(milestone, completed);
    } catch (_) {
      /* The controller keeps the mutation error visible in the page. */
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          if (state.isLoading && state.error == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.project == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('项目')),
              body: Center(child: Text(state.error ?? '项目不存在')),
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(
                state.project!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: '编辑项目',
                  onPressed: state.isSaving ? null : () => _editProject(state),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Tasks'),
                  Tab(text: 'Milestones'),
                  Tab(text: 'Timeline'),
                ],
              ),
            ),
            body: Column(
              children: [
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _overview(state),
                      _tasks(state),
                      _milestones(state),
                      _timeline(state),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _overview(ProjectState state) {
    final project = state.project!;
    final completedTasks = state.tasks
        .where((task) => task.status == TaskStatus.completed)
        .length;
    final completedMilestones = state.milestones
        .where((milestone) => milestone.completedAt != null)
        .length;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('项目目标', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(project.objective.isEmpty ? '尚未填写项目目标' : project.objective),
        const SizedBox(height: 24),
        Text(
          '进度 ${state.progress.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: state.progress / 100,
          semanticsLabel: '项目进度',
          semanticsValue: '${state.progress.toStringAsFixed(1)}%',
        ),
        const SizedBox(height: 8),
        Text(
          '$completedTasks / ${state.tasks.length} 项任务完成 · $completedMilestones / ${state.milestones.length} 个里程碑完成',
        ),
        const SizedBox(height: 24),
        Text(
          project.deadline == null
              ? '未设置截止日期'
              : '截止日期 ${projectDateLabel(project.deadline!)}',
        ),
        if (widget.onShowQuadrant != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => widget.onShowQuadrant!(project.id),
              icon: const Icon(Icons.scatter_plot_outlined),
              label: const Text('在象限中查看'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tasks(ProjectState state) {
    if (state.tasks.isEmpty) {
      return const Center(child: Text('暂无项目任务，可在任务详情中关联项目'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.tasks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _taskTile(state.tasks[index]),
    );
  }

  Widget _taskTile(Task task) => ListTile(
    title: Text(task.title),
    leading: Icon(
      task.status == TaskStatus.completed
          ? Icons.check_circle_outline
          : Icons.task_alt_outlined,
    ),
    subtitle: Text(
      '${_statusLabel(task.status)} · ${task.status == TaskStatus.completed ? 100 : task.progress}%${task.deadline == null ? '' : ' · 截止 ${projectDateLabel(task.deadline!)}'}',
    ),
    onTap: widget.onOpenTask == null ? null : () => widget.onOpenTask!(task.id),
  );

  Widget _milestones(ProjectState state) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: state.isSaving ? null : () => _editMilestone(null),
          icon: const Icon(Icons.add),
          label: const Text('新建里程碑'),
        ),
      ),
      const SizedBox(height: 16),
      if (state.milestones.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Text('暂无里程碑')),
      for (final milestone in state.milestones) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: Key('milestone-complete-${milestone.id}'),
              value: milestone.completedAt != null,
              semanticLabel: '${milestone.name} 完成状态',
              onChanged: state.isSaving
                  ? null
                  : (completed) =>
                        _completeMilestone(milestone, completed ?? false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      milestone.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${milestone.completedAt == null ? '未完成' : '已完成'}${milestone.deadline == null ? ' · 未设置截止日期' : ' · 截止 ${projectDateLabel(milestone.deadline!)}'}',
                    ),
                    Text('${state.milestoneTasks(milestone.id).length} 项关联任务'),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '编辑里程碑',
              onPressed: state.isSaving
                  ? null
                  : () => _editMilestone(milestone),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        for (final task in state.milestoneTasks(milestone.id))
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: _taskTile(task),
          ),
        const Divider(height: 1),
      ],
    ],
  );

  Widget _timeline(ProjectState state) {
    final events = state.timeline;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final event = events[index];
        return ListTile(
          leading: Icon(
            event.milestoneId != null
                ? Icons.flag_outlined
                : event.taskId != null
                ? Icons.task_outlined
                : Icons.folder_outlined,
          ),
          title: Text('${event.kind} · ${event.title}'),
          subtitle: Text(projectDateLabel(event.date)),
          onTap: event.taskId == null || widget.onOpenTask == null
              ? null
              : () => widget.onOpenTask!(event.taskId!),
        );
      },
    );
  }

  String _statusLabel(TaskStatus status) => switch (status) {
    TaskStatus.inbox => '收件箱',
    TaskStatus.planned => '已规划',
    TaskStatus.inProgress => '进行中',
    TaskStatus.waiting => '等待中',
    TaskStatus.completed => '已完成',
    TaskStatus.cancelled => '已取消',
  };
}
