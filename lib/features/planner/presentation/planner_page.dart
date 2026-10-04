import 'package:flutter/material.dart';

import '../../../domain/planning/planned_block.dart';
import '../../settings/data/work_schedule_repository.dart';
import '../../settings/presentation/work_time_input.dart';
import '../application/planner_controller.dart';
import 'day_timeline.dart';
import 'planner_block_card.dart';
import 'weekend_override_dialog.dart';

class PlannerPage extends StatefulWidget {
  final PlannerController controller;
  final ValueChanged<String>? onOpenTask;
  final void Function(String, String?)? onStartFocus;
  const PlannerPage({
    super.key,
    required this.controller,
    this.onOpenTask,
    this.onStartFocus,
  });
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  PlannerController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.start();
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

  Future<void> _edit(PlannedBlock b) async {
    var start = formatMinute(b.start.hour * 60 + b.start.minute);
    var end = formatMinute(b.end.hour * 60 + b.end.minute);
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('修改计划时间'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: start,
                onChanged: (value) => start = value,
                decoration: const InputDecoration(labelText: '开始时间'),
              ),
              TextFormField(
                initialValue: end,
                onChanged: (value) => end = value,
                decoration: const InputDecoration(labelText: '结束时间'),
              ),
              if (error != null) Text(error!),
            ],
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
                        await c.move(
                          b.id,
                          c.date.add(Duration(minutes: parseMinute(start))),
                          c.date.add(Duration(minutes: parseMinute(end))),
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
              child: const Text('保存时间'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDate({String? deferTaskId}) async {
    final next = await showDatePicker(
      context: context,
      initialDate: c.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || next == null) return;
    if (deferTaskId == null) {
      c.selectDate(next);
    } else {
      await _action(() => c.defer(deferTaskId, next));
    }
  }

  Widget _block(PlannedBlock b) {
    final saved = c.blocks.any((old) => old.id == b.id);
    final task = c.task(b.taskId);
    final reasons = c.candidates
        .where((candidate) => candidate.task.id == b.taskId)
        .expand((candidate) => candidate.reasons.map((r) => r.message))
        .toList();
    return PlannerBlockCard(
      key: ValueKey('planner-block-${b.id}'),
      block: b,
      title: task?.title ?? '任务',
      reasons: reasons,
      editable: saved && !c.busy,
      onLock: () => _action(() => c.lock(b.id, !b.isLocked)),
      onMoveMinutes: (minutes) => _action(
        () => c.move(
          b.id,
          b.start.add(Duration(minutes: minutes)),
          b.end.add(Duration(minutes: minutes)),
        ),
      ),
      onReorder: (direction) => _action(() => c.reorder(b.id, direction)),
      onEditTime: () => _edit(b),
      onOpenTask: widget.onOpenTask == null
          ? null
          : () => widget.onOpenTask!(b.taskId),
      onStartFocus:
          !saved ||
              widget.onStartFocus == null ||
              task == null ||
              (task.status.name != 'planned' &&
                  task.status.name != 'inProgress')
          ? null
          : () => widget.onStartFocus!(b.taskId, b.id),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('规划')),
    body: AnimatedBuilder(
      animation: c,
      builder: (context, _) => ListView(
        key: const PageStorageKey('planner-workspace'),
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: '前一天',
                onPressed: () =>
                    c.selectDate(c.date.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: _chooseDate,
                child: Text(localDateKey(c.date)),
              ),
              IconButton(
                tooltip: '后一天',
                onPressed: () =>
                    c.selectDate(c.date.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
              FilledButton(
                onPressed: c.busy ? null : () => _action(c.replan),
                child: const Text('重新规划'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => WeekendOverrideDialog(
                      date: c.date,
                      schedules: c.schedules,
                      initialWindows: c.calendar.schedule.dateOverride(c.date),
                    ),
                  );
                  await c.refresh();
                },
                child: const Text('单日临时时段'),
              ),
            ],
          ),
          if (c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          if (c.calendar.availableWindows(c.date).isEmpty)
            const Text('当天没有可用工作时段，周末默认不安排任务。可以添加单日临时时段。'),
          if (c.blocks.isEmpty && c.suggestion.blocks.isNotEmpty)
            const Text('当前为建议，点击重新规划保存为今日计划。'),
          DayTimeline(
            blocks: c.blocks.isEmpty ? c.suggestion.blocks : c.blocks,
            windows: c.calendar.availableWindows(c.date),
            blockBuilder: _block,
            onDrop: (b, minute) => _action(
              () => c.move(
                b.id,
                c.date.add(Duration(minutes: minute)),
                c.date.add(Duration(minutes: minute + b.durationMinutes)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('任务与人工覆盖', style: Theme.of(context).textTheme.titleLarge),
          for (final task in c.taskList.where(
            (t) => t.status.name == 'planned' || t.status.name == 'inProgress',
          ))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title),
                    if (c.overrides[task.id] != null)
                      Text(switch (c.overrides[task.id]) {
                        'skip' => '当天跳过',
                        'pin' => '人工置顶并保留时段',
                        _ => '提高优先级',
                      }),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: c.busy
                              ? null
                              : () => _action(() => c.pin(task.id)),
                          child: const Text('Pin to Today'),
                        ),
                        TextButton(
                          onPressed: c.busy
                              ? null
                              : () => _action(() => c.skip(task.id)),
                          child: const Text('Skip Today'),
                        ),
                        TextButton(
                          onPressed: c.busy
                              ? null
                              : () => _action(() => c.raisePriority(task.id)),
                          child: const Text('提高优先级'),
                        ),
                        TextButton(
                          onPressed: c.busy
                              ? null
                              : () => _chooseDate(deferTaskId: task.id),
                          child: const Text('延期'),
                        ),
                        if (c.overrides.containsKey(task.id))
                          TextButton(
                            onPressed: () => _action(() async {
                              await c.plans.clearOverride(task.id, c.date);
                              await c.replan();
                            }),
                            child: const Text('撤销覆盖'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (c.suggestion.unscheduled.isNotEmpty)
            Text('尚未安排', style: Theme.of(context).textTheme.titleLarge),
          for (final item in c.suggestion.unscheduled)
            ListTile(
              title: Text(item.candidate.task.title),
              subtitle: Text(
                item.remainingMinutes == null
                    ? '请先填写预计时长'
                    : '可用时段不足，剩余 ${item.remainingMinutes} 分钟',
              ),
              onTap: widget.onOpenTask == null
                  ? null
                  : () => widget.onOpenTask!(item.candidate.task.id),
            ),
        ],
      ),
    ),
  );
}
