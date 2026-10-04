import 'package:flutter/material.dart';

import '../../../domain/planning/work_schedule.dart';
import '../data/work_schedule_repository.dart';
import 'work_time_input.dart';

class WorkScheduleSettings extends StatefulWidget {
  final WorkScheduleRepository schedules;
  const WorkScheduleSettings({super.key, required this.schedules});
  @override
  State<WorkScheduleSettings> createState() => _WorkScheduleSettingsState();
}

class _WorkScheduleSettingsState extends State<WorkScheduleSettings> {
  final _fields = [for (var i = 0; i < 5; i++) TextEditingController()];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _success;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final calendar = await widget.schedules.getCalendar();
      if (!mounted) return;
      for (var i = 0; i < _fields.length; i++) {
        _fields[i].text = calendar.schedule
            .windowsForWeekday(i + 1)
            .map(
              (w) =>
                  '${formatMinute(w.startMinutes)}–${formatMinute(w.endMinutes)}',
            )
            .join(', ');
      }
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '工作时间读取失败：$e';
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final windows = <int, List<TimeWindow>>{
        for (var i = 0; i < _fields.length; i++)
          i + 1: parseWindows(_fields[i].text),
      };
      await widget.schedules.saveWeekdays(windows);
      if (mounted) setState(() => _success = '工作时间已保存');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('工作时间', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('12:00–14:00 为午休。周末默认不安排，可在规划页添加单日临时时段。'),
      const Text('多个时段用逗号分隔；留空表示当天不工作。'),
      for (var i = 0; i < _fields.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            key: ValueKey('schedule-weekday-${i + 1}'),
            controller: _fields[i],
            enabled: !_busy && !_loading,
            decoration: InputDecoration(
              labelText: ['周一时段', '周二时段', '周三时段', '周四时段', '周五时段'][i],
              hintText: '09:00–12:00, 14:00–18:00',
            ),
          ),
        ),
      const SizedBox(height: 12),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_success != null) Text(_success!),
      FilledButton(
        onPressed: _busy || _loading ? null : _save,
        child: const Text('保存工作时间'),
      ),
    ],
  );
}
