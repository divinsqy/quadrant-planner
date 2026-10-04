import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_tokens.dart';
import '../../inbox/presentation/quick_capture.dart';
import '../../tasks/application/task_editor_controller.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/presentation/task_preview_drawer.dart';
import '../../projects/data/project_repository.dart';
import '../../tasks/data/task_activity_repository.dart';
import '../../../domain/tasks/task_activity_event.dart';
import '../application/activity_trajectory.dart';
import '../quadrant/task_trajectory_builder.dart';
import '../application/dashboard_controller.dart';
import '../quadrant/quadrant_board.dart';
import '../quadrant/quadrant_models.dart';

class DashboardPage extends StatefulWidget {
  final DashboardController controller;
  final TaskRepository taskRepository;
  final TaskEditorController? taskEditor;
  final VoidCallback? onOpenSearch;
  final ValueChanged<String>? onOpenTask;
  final ValueChanged<String>? onStartFocus;
  final ProjectRepository? projects;
  final TaskActivityRepository? activity;

  const DashboardPage({
    super.key,
    required this.controller,
    required this.taskRepository,
    this.taskEditor,
    this.onOpenSearch,
    this.onOpenTask,
    this.onStartFocus,
    this.projects,
    this.activity,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  StreamSubscription<List<TaskActivityEvent>>? _activitySubscription;
  String? _trajectoryTaskId;
  int _trajectoryVersion = 0;
  List<TaskTrajectoryPoint> _trajectory = const [];
  final ScrollController _workspaceScroll = ScrollController();
  final ScrollController _taskScroll = ScrollController();
  final ScrollController _pageScroll = ScrollController();
  Timer? _refreshTimer;
  String? get _selectedTaskId => widget.controller.state.selectedTaskId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.start();
    _watchTrajectory();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => widget.controller.refresh(),
    );
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _activitySubscription?.cancel();
    _trajectoryVersion++;
    _workspaceScroll.dispose();
    _taskScroll.dispose();
    _pageScroll.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
      _watchTrajectory();
    }
  }

  void _selectTask(String id) {
    widget.controller.selectTask(id);
  }

  void _watchTrajectory() {
    final id = _selectedTaskId;
    if (_trajectoryTaskId == id) return;
    _trajectoryTaskId = id;
    _activitySubscription?.cancel();
    _trajectoryVersion++;
    _trajectory = const [];
    if (id == null || widget.activity == null) return;
    _activitySubscription = widget.activity!
        .watchRecent(id, limit: 1)
        .listen((_) => _loadTrajectory(id));
  }

  Future<void> _loadTrajectory(String id) async {
    final version = ++_trajectoryVersion;
    try {
      final task = await widget.taskRepository.get(id);
      if (task == null || !mounted || version != _trajectoryVersion) return;
      final now = widget.controller.now;
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6));
      final created = task.createdAt.toLocal();
      final from = created.isAfter(weekStart)
          ? DateTime(created.year, created.month, created.day)
          : weekStart;
      if (from.isAfter(now)) return;
      final events = <TaskActivityEvent>[];
      DateTime? before;
      String? beforeId;
      while (true) {
        final page = await widget.activity!.fetchPage(
          id,
          limit: 100,
          before: before,
          beforeId: beforeId,
        );
        events.addAll(page.where((e) => !e.occurredAt.isBefore(from.toUtc())));
        if (page.length < 100 || page.last.occurredAt.isBefore(from.toUtc())) {
          break;
        }
        before = page.last.occurredAt;
        beforeId = page.last.id;
        if (!mounted || version != _trajectoryVersion) return;
      }
      final points = ActivityTrajectory(calendar: widget.controller.calendar)
          .build(task: task, events: events, from: from, to: now);
      if (mounted && version == _trajectoryVersion) {
        setState(() => _trajectory = points);
      }
    } catch (_) {
      // A history failure must not disable the live local task workspace.
      if (mounted && version == _trajectoryVersion) {
        setState(() => _trajectory = const []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final recommendation = state.currentRecommendation;
    final selectedMatches = state.snapshots.where(
      (snapshot) => snapshot.task.id == _selectedTaskId,
    );
    final selectedTask = selectedMatches.isEmpty
        ? null
        : selectedMatches.first.task;

    final dashboard = Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 980 || constraints.maxHeight < 600;
              final children = <Widget>[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.controller.greeting,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '搜索',
                      onPressed: widget.onOpenSearch,
                      icon: const Icon(Icons.search_rounded),
                    ),
                    const SizedBox(width: 8),
                    const Chip(
                      avatar: Icon(Icons.cloud_done_outlined, size: 18),
                      label: Text('本地已保存'),
                    ),
                  ],
                ),
                Text(
                  '${widget.controller.now.year}年${widget.controller.now.month}月${widget.controller.now.day}日',
                ),
                const SizedBox(height: 16),
                QuickCapture(taskRepository: widget.taskRepository),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.projects != null)
                      _ProjectFilter(
                        projects: widget.projects!,
                        selected: state.projectId,
                        onChanged: widget.controller.filterProject,
                      ),
                    Text(
                      '阈值：紧急性 ${state.preferences.urgencyThreshold} / 重要性 ${state.preferences.importanceThreshold}',
                    ),
                    TextButton.icon(
                      onPressed: () => widget.controller.setListExpanded(
                        !state.listExpanded,
                      ),
                      icon: Icon(
                        state.listExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      label: Text(state.listExpanded ? '收起任务列表' : '展开任务列表'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: compact ? 900 : null,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final quadrant = _Surface(
                        title: '实时四象限',
                        child: QuadrantBoard(
                          tasks: state.snapshots,
                          thresholds: QuadrantThresholds(
                            urgency: state.preferences.urgencyThreshold,
                            importance: state.preferences.importanceThreshold,
                          ),
                          selectedTaskId: _selectedTaskId,
                          trajectory: _trajectory,
                          taskMetadata: state.taskMetadata,
                          onSelect: _selectTask,
                          onOpen: widget.onOpenTask,
                          onThresholdChanged: (thresholds) {
                            widget.controller
                                .updateThresholds(thresholds)
                                .catchError((Object error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('阈值保存失败：$error')),
                                    );
                                  }
                                });
                          },
                        ),
                      );

                      final focus =
                          selectedTask != null && widget.taskEditor != null
                          ? _Surface(
                              title: '任务详情',
                              child: TaskPreviewDrawer(
                                task: selectedTask,
                                controller: widget.taskEditor!,
                                projects: widget.projects,
                                onClose: () =>
                                    widget.controller.selectTask(null),
                                onOpenDetail: widget.onOpenTask == null
                                    ? null
                                    : () => widget.onOpenTask!(selectedTask.id),
                              ),
                            )
                          : _Surface(
                              title: '现在做什么',
                              child: recommendation == null
                                  ? const Text('当前没有可执行任务')
                                  : SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            recommendation.task.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 12),
                                          if (widget.onStartFocus != null)
                                            FilledButton(
                                              onPressed: () =>
                                                  widget.onStartFocus!(
                                                    recommendation.task.id,
                                                  ),
                                              child: const Text('开始专注'),
                                            ),
                                          OutlinedButton(
                                            onPressed: () => _selectTask(
                                              recommendation.task.id,
                                            ),
                                            child: const Text('查看推荐任务'),
                                          ),
                                          for (final block
                                              in state.todayPlan.blocks.take(3))
                                            Text(
                                              '${_time(block.start)}–${_time(block.end)} · ${_taskTitle(block.taskId)}',
                                            ),
                                          const SizedBox(height: 8),
                                          for (final reason
                                              in recommendation.reasons.take(3))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              child: Text(
                                                '• ${reason.message}',
                                              ),
                                            ),
                                          const SizedBox(height: 12),
                                          Text(
                                            '今日已规划 '
                                            '${state.todayPlan.blocks.length} '
                                            '个时间块',
                                          ),
                                        ],
                                      ),
                                    ),
                            );

                      final taskList = _Surface(
                        title: '任务列表',
                        child: state.snapshots.isEmpty
                            ? const Text('还没有已规划任务')
                            : ListView.builder(
                                controller: _taskScroll,
                                itemCount: state.snapshots.length,
                                itemBuilder: (context, index) {
                                  final snapshot = state.snapshots[index];
                                  return ListTile(
                                    dense: true,
                                    selected:
                                        snapshot.task.id == _selectedTaskId,
                                    title: Text(snapshot.task.title),
                                    subtitle: Text(
                                      '重要性 ${snapshot.task.importance} · '
                                      '紧急性 ${snapshot.currentUrgency}',
                                    ),
                                    onTap: () => _selectTask(snapshot.task.id),
                                  );
                                },
                              ),
                      );

                      if (constraints.maxWidth < 980) {
                        return ListView(
                          controller: _workspaceScroll,
                          children: [
                            SizedBox(height: 300, child: quadrant),
                            const SizedBox(height: 16),
                            SizedBox(height: 270, child: focus),
                            if (state.listExpanded) ...[
                              const SizedBox(height: 16),
                              SizedBox(height: 240, child: taskList),
                            ],
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 2, child: quadrant),
                                const SizedBox(width: 16),
                                Expanded(child: focus),
                              ],
                            ),
                          ),
                          if (state.listExpanded) ...[
                            const SizedBox(height: 16),
                            Expanded(child: taskList),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ];
              return compact
                  ? ListView(controller: _pageScroll, children: children)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...children.take(children.length - 1),
                        Expanded(child: children.last),
                      ],
                    );
            },
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        if (selectedTask != null)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              widget.controller.selectTask(null),
      },
      child: dashboard,
    );
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  String _taskTitle(String id) => widget.controller.state.snapshots
      .map((s) => s.task)
      .firstWhere((t) => t.id == id)
      .title;
}

class _ProjectFilter extends StatelessWidget {
  final ProjectRepository projects;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _ProjectFilter({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: projects.watchAll(),
    builder: (context, snapshot) => SizedBox(
      width: 240,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey((selected, snapshot.hasData)),
        initialValue:
            snapshot.data?.any((project) => project.id == selected) == true
            ? selected
            : null,
        decoration: const InputDecoration(labelText: '项目筛选'),
        items: [
          const DropdownMenuItem(value: null, child: Text('全部项目')),
          for (final project in snapshot.data ?? [])
            DropdownMenuItem(
              value: project.id,
              child: Text(project.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}

class _Surface extends StatelessWidget {
  final String title;
  final Widget child;

  const _Surface({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMedium),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
