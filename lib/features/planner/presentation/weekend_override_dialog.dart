import 'package:flutter/material.dart';

import '../../../domain/planning/work_schedule.dart';
import '../../settings/data/work_schedule_repository.dart';
import '../../settings/presentation/work_time_input.dart';

class WeekendOverrideDialog extends StatefulWidget {
  final DateTime date;
  final WorkScheduleRepository schedules;
  final List<TimeWindow> initialWindows;
  const WeekendOverrideDialog({
    super.key,
    required this.date,
    required this.schedules,
    this.initialWindows = const [],
  });
  @override
  State<WeekendOverrideDialog> createState() => _WeekendOverrideDialogState();
}

class _WeekendOverrideDialogState extends State<WeekendOverrideDialog> {
  late final List<(TextEditingController, TextEditingController)> _rows = [
    for (final w
        in widget.initialWindows.isEmpty
            ? [const TimeWindow(startMinutes: 600, endMinutes: 720)]
            : widget.initialWindows)
      (
        TextEditingController(text: formatMinute(w.startMinutes)),
        TextEditingController(text: formatMinute(w.endMinutes)),
      ),
  ];
  bool _busy = false;
  String? _error;
  Future<void> _save({bool clear = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (clear) {
        await widget.schedules.clearDateOverride(widget.date);
      } else {
        await widget.schedules.setDateOverride(
          widget.date,
          _rows
              .map(
                (r) => TimeWindow(
                  startMinutes: parseMinute(r.$1.text),
                  endMinutes: parseMinute(r.$2.text),
                ),
              )
              .toList(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.$1.dispose();
      row.$2.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${localDateKey(widget.date)} 临时时段'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('仅影响这一天。12:00–14:00 保留为午休。'),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: i == 0 ? const ValueKey('override-start') : null,
                      controller: _rows[i].$1,
                      decoration: const InputDecoration(labelText: '开始时间'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: i == 0 ? const ValueKey('override-end') : null,
                      controller: _rows[i].$2,
                      decoration: const InputDecoration(labelText: '结束时间'),
                    ),
                  ),
                  IconButton(
                    tooltip: '移除此时段',
                    onPressed: _busy || _rows.length == 1
                        ? null
                        : () {
                            final removed = _rows.removeAt(i);
                            removed.$1.dispose();
                            removed.$2.dispose();
                            setState(() {});
                          },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(
                    () => _rows.add((
                      TextEditingController(text: '14:00'),
                      TextEditingController(text: '16:00'),
                    )),
                  ),
            child: const Text('添加时段'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      if (widget.initialWindows.isNotEmpty)
        TextButton(
          onPressed: _busy ? null : () => _save(clear: true),
          child: const Text('移除临时覆盖'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('保存临时时段'),
      ),
    ],
  );
}
