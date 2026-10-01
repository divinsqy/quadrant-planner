import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../inbox/presentation/quick_capture.dart';
import '../../tasks/application/task_editor_controller.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/presentation/task_preview_drawer.dart';
import '../application/dashboard_controller.dart';
import '../quadrant/quadrant_board.dart';
import '../quadrant/quadrant_models.dart';

class DashboardPage extends StatefulWidget {
  final DashboardController controller;
  final TaskRepository taskRepository;
  final TaskEditorController? taskEditor;
  final VoidCallback? onOpenSearch;
  final ValueChanged<String>? onOpenTask;

  const DashboardPage({
    super.key,
    required this.controller,
    required this.taskRepository,
    this.taskEditor,
    this.onOpenSearch,
    this.onOpenTask,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _selectedTaskId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.start();
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
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _selectTask(String id) {
    setState(() => _selectedTaskId = id);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final recommendation = state.currentRecommendation;
    final selectedSnapshot = state.snapshots
        .where((snapshot) => snapshot.task.id == _selectedTaskId)
        .firstOrNull;
    final selectedTask = selectedSnapshot?.task;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 16),
              QuickCapture(taskRepository: widget.taskRepository),
              const SizedBox(height: 20),
              Expanded(
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
                        onSelect: _selectTask,
                        onOpen: widget.onOpenTask,
                        onThresholdChanged: (thresholds) {
                          widget.controller.updateThresholds(thresholds);
                        },
                      ),
                    );

                    final focus = selectedTask != null &&
                            widget.taskEditor != null
                        ? _Surface(
                            title: '任务详情',
                            child: TaskPreviewDrawer(
                              task: selectedTask,
                              controller: widget.taskEditor!,
                              onClose: () =>
                                  setState(() => _selectedTaskId = null),
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
                                        const SizedBox(height: 8),
                                        for (final reason
                                            in recommendation.reasons.take(3))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text('• ${reason.message}'),
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
                                  onTap: () =>
                                      _selectTask(snapshot.task.id),
                                );
                              },
                            ),
                    );

                    if (constraints.maxWidth < 980) {
                      return ListView(
                        children: [
                          SizedBox(height: 300, child: quadrant),
                          const SizedBox(height: 16),
                          SizedBox(height: 270, child: focus),
                          const SizedBox(height: 16),
                          SizedBox(height: 240, child: taskList),
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
                        const SizedBox(height: 16),
                        Expanded(child: taskList),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  final String title;
  final Widget child;

  const _Surface({
    required this.title,
    required this.child,
  });

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
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
