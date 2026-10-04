import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/focus/focus_session.dart';
import '../../../domain/tasks/subtask.dart';
import '../../../domain/tasks/task.dart';
import '../../tasks/data/task_repository.dart';
import '../../reports/data/weekly_note_repository.dart';
import '../../reports/presentation/weekly_note_dialog.dart';
import '../application/focus_controller.dart';

class FocusPage extends StatefulWidget {
  final FocusController controller;
  final TaskRepository tasks;
  final VoidCallback? onShowPlanner;
  final WeeklyNoteRepository? weeklyNotes;
  const FocusPage({
    super.key,
    required this.controller,
    required this.tasks,
    this.onShowPlanner,
    this.weeklyNotes,
  });
  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  Timer? _ticker;
  FocusController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.watch();
    if (c.session == null) {
      c.recover().catchError((Object e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('专注恢复失败：$e')));
        }
      });
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && c.session?.state == FocusSessionState.running) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _complete() async {
    final session = c.session;
    if (session == null || !session.isActive) return;
    final count = await c.repository.futureBlockCount(session.taskId, c.now);
    if (!mounted) return;
    bool finishTask = true;
    bool clearFuture = false;
    bool busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('完成专注'),
          scrollable: true,
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('实际用时将单独记录，预计时长保持不变。'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('同时标记任务完成'),
                  value: finishTask,
                  onChanged: busy
                      ? null
                      : (v) => update(() {
                          finishTask = v ?? true;
                          if (!finishTask) clearFuture = false;
                        }),
                ),
                if (count > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('移除此任务后续 $count 个未完成计划块'),
                    subtitle: const Text('未勾选时保留后续计划。其他任务不受影响。'),
                    value: clearFuture,
                    onChanged: busy || !finishTask
                        ? null
                        : (v) => update(() => clearFuture = v ?? false),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await c.complete(
                          completeTask: finishTask,
                          removeFutureBlocks: clearFuture,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        if (ctx.mounted) {
                          update(() {
                            busy = false;
                            error = '$e';
                          });
                        }
                      }
                    },
              child: const Text('确认完成'),
            ),
          ],
        ),
      ),
    );
  }

  String _elapsed() {
    final seconds = c.elapsed.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('专注')),
    body: AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final session = c.session;
        if (session == null) return const Center(child: Text('当前没有专注会话'));
        return StreamBuilder<Task?>(
          stream: widget.tasks.watchTask(session.taskId),
          builder: (context, snapshot) {
            final task = snapshot.data;
            final estimate = task?.estimatedMinutes;
            final remaining = estimate == null
                ? null
                : math.max(0, estimate * 60 - c.totalTaskDuration.inSeconds);
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  task?.title ?? '读取任务…',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                Text(
                  '已专注 ${_elapsed()}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  estimate == null
                      ? '预计剩余：未填写估算'
                      : '预计：$estimate 分钟 · 预计剩余 ${(remaining! / 60).ceil()} 分钟',
                ),
                Text(switch (session.state) {
                  FocusSessionState.running => '正在专注',
                  FocusSessionState.paused => '已暂停',
                  FocusSessionState.completed => '专注已完成',
                  FocusSessionState.blocked => '专注已阻塞',
                }),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (widget.weeklyNotes != null)
                      Tooltip(
                        message: '记录本周笔记',
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.note_add_outlined),
                          label: const Text('记录本周笔记'),
                          onPressed: c.busy
                              ? null
                              : () => showWeeklyNoteDialog(
                                  context,
                                  notes: widget.weeklyNotes!,
                                  weekStart: c.now,
                                  taskId: session.taskId,
                                ),
                        ),
                      ),
                    if (session.state == FocusSessionState.running)
                      OutlinedButton(
                        onPressed: c.busy ? null : () => _action(c.pause),
                        child: const Text('暂停'),
                      ),
                    if (session.state == FocusSessionState.paused)
                      FilledButton(
                        onPressed: c.busy ? null : () => _action(c.resume),
                        child: const Text('继续'),
                      ),
                    if (session.isActive)
                      FilledButton(
                        onPressed: c.busy ? null : _complete,
                        child: const Text('完成'),
                      ),
                    if (session.isActive)
                      OutlinedButton(
                        onPressed: c.busy ? null : () => _action(c.markBlocked),
                        child: const Text('标记阻塞'),
                      ),
                    if (widget.onShowPlanner != null)
                      TextButton(
                        onPressed: widget.onShowPlanner,
                        child: const Text('查看规划'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('子任务', style: Theme.of(context).textTheme.titleLarge),
                StreamBuilder<List<Subtask>>(
                  stream: widget.tasks.relations.watchSubtasks(session.taskId),
                  builder: (context, subtaskSnapshot) => Column(
                    children: [
                      if ((subtaskSnapshot.data ?? []).isEmpty)
                        const Text('暂无子任务'),
                      for (final subtask in subtaskSnapshot.data ?? <Subtask>[])
                        CheckboxListTile(
                          title: Text(subtask.title),
                          value: subtask.completed,
                          onChanged: !session.isActive
                              ? null
                              : (value) => _action(
                                  () => widget.tasks.relations.updateSubtask(
                                    subtask.id,
                                    completed: value ?? false,
                                  ),
                                ),
                        ),
                    ],
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
