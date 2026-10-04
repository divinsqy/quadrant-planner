import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/planning/planned_block.dart';
import '../../settings/presentation/work_time_input.dart';

class PlannerBlockCard extends StatelessWidget {
  final PlannedBlock block;
  final String title;
  final List<String> reasons;
  final bool editable;
  final ValueChanged<int>? onMoveMinutes;
  final ValueChanged<int>? onReorder;
  final VoidCallback? onEditTime;
  final VoidCallback? onLock;
  final VoidCallback? onStartFocus;
  final VoidCallback? onOpenTask;
  const PlannerBlockCard({
    super.key,
    required this.block,
    required this.title,
    this.reasons = const [],
    this.editable = true,
    this.onMoveMinutes,
    this.onReorder,
    this.onEditTime,
    this.onLock,
    this.onStartFocus,
    this.onOpenTask,
  });
  @override
  Widget build(BuildContext context) {
    final movable = editable && !block.isLocked && block.completedAt == null;
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatMinute(block.start.hour * 60 + block.start.minute)}–${formatMinute(block.end.hour * 60 + block.end.minute)} · $title',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${block.durationMinutes} 分钟${block.completedAt == null ? '' : ' · 已完成'}${block.source == PlanBlockSource.manual ? ' · 人工安排' : ''}',
            ),
            for (final reason in reasons) Text(reason),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: block.isLocked ? '解锁时段' : '锁定时段',
                  onPressed: editable && block.completedAt == null
                      ? onLock
                      : null,
                  icon: Icon(block.isLocked ? Icons.lock : Icons.lock_open),
                ),
                IconButton(
                  tooltip: '提前15分钟',
                  onPressed: movable ? () => onMoveMinutes?.call(-15) : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '延后15分钟',
                  onPressed: movable ? () => onMoveMinutes?.call(15) : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: '向前重排',
                  onPressed: movable ? () => onReorder?.call(-1) : null,
                  icon: const Icon(Icons.keyboard_double_arrow_up),
                ),
                IconButton(
                  tooltip: '向后重排',
                  onPressed: movable ? () => onReorder?.call(1) : null,
                  icon: const Icon(Icons.keyboard_double_arrow_down),
                ),
                IconButton(
                  tooltip: '修改时间',
                  onPressed: movable ? onEditTime : null,
                  icon: const Icon(Icons.edit_calendar),
                ),
                if (onOpenTask != null)
                  TextButton(onPressed: onOpenTask, child: const Text('任务详情')),
                if (onStartFocus != null && block.completedAt == null)
                  FilledButton.tonal(
                    onPressed: onStartFocus,
                    child: const Text('开始专注'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () {
          if (movable) onMoveMinutes?.call(-15);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () {
          if (movable) onMoveMinutes?.call(15);
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () {
          if (movable) onReorder?.call(-1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () {
          if (movable) onReorder?.call(1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true): () {
          if (movable) onReorder?.call(-1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true): () {
          if (movable) onReorder?.call(1);
        },
      },
      child: Focus(
        child: movable
            ? Draggable<PlannedBlock>(
                data: block,
                feedback: Material(
                  child: SizedBox(
                    width: 260,
                    child: Text('$title · ${block.durationMinutes} 分钟'),
                  ),
                ),
                childWhenDragging: Opacity(opacity: .4, child: card),
                child: card,
              )
            : card,
      ),
    );
  }
}
