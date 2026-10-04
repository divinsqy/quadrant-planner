import 'package:flutter/material.dart';

import '../../../domain/planning/planned_block.dart';
import '../../../domain/planning/work_schedule.dart';
import '../../settings/presentation/work_time_input.dart';

class DayTimeline extends StatelessWidget {
  final List<PlannedBlock> blocks;
  final List<TimeWindow> windows;
  final Widget Function(PlannedBlock) blockBuilder;
  final void Function(PlannedBlock, int) onDrop;
  const DayTimeline({
    super.key,
    required this.blocks,
    required this.windows,
    required this.blockBuilder,
    required this.onDrop,
  });
  @override
  Widget build(BuildContext context) {
    final windowFirst = windows.fold<int>(
      9,
      (n, w) => w.startMinutes ~/ 60 < n ? w.startMinutes ~/ 60 : n,
    );
    final windowLast = windows.fold<int>(
      18,
      (n, w) => (w.endMinutes / 60).ceil() > n ? (w.endMinutes / 60).ceil() : n,
    );
    final first = blocks.fold<int>(
      windowFirst,
      (n, b) => b.start.hour < n ? b.start.hour : n,
    );
    final last = blocks.fold<int>(windowLast, (n, b) {
      final endHour = b.end.day != b.start.day
          ? 24
          : b.end.hour + (b.end.minute > 0 ? 1 : 0);
      return endHour > n ? endHour : n;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var hour = first; hour < last; hour++)
          if (hour != 13)
            DragTarget<PlannedBlock>(
              key: ValueKey('planner-slot-${hour * 60}'),
              onAcceptWithDetails: (details) => onDrop(details.data, hour * 60),
              builder: (context, accepted, rejected) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hour == 12
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : accepted.isNotEmpty
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      hour == 12
                          ? '12:00–14:00 午休 · 不可用'
                          : formatMinute(hour * 60),
                    ),
                    for (final b in blocks.where((b) => b.start.hour == hour))
                      blockBuilder(b),
                    if (!blocks.any((b) => b.start.hour == hour))
                      const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
