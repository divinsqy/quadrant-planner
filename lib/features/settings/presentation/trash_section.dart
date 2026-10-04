import 'package:flutter/material.dart';

import '../../tasks/data/trash_repository.dart';

class TrashSection extends StatefulWidget {
  final TrashRepository repository;
  const TrashSection({super.key, required this.repository});
  @override
  State<TrashSection> createState() => _TrashSectionState();
}

class _TrashSectionState extends State<TrashSection> {
  late Future<List<TrashItem>> _items = widget.repository.list();
  String? _message;
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _items = widget.repository.list());
    } catch (_) {
      if (mounted) setState(() => _message = '操作未完成，数据已保留。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('回收站', style: Theme.of(context).textTheme.titleLarge),
      const Text('删除记录保留至少30天。清理会等待同步删除确认及冲突解决。'),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _run(() async {
                final count = await widget.repository.purgeEligible();
                if (mounted) setState(() => _message = '已清理 $count 条到期记录');
              }),
        child: const Text('清理到期记录'),
      ),
      FutureBuilder<List<TrashItem>>(
        future: _items,
        builder: (context, snapshot) => Column(
          children: [
            for (final item in snapshot.data ?? <TrashItem>[])
              ListTile(
                title: Text(item.title),
                subtitle: Text(
                  '${item.kind} · ${item.deletedAt.toLocal().toString().split(' ').first}',
                ),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.repository.restore(item.kind, item.id),
                        ),
                  child: const Text('恢复'),
                ),
              ),
          ],
        ),
      ),
      if (_message != null) Text(_message!),
    ],
  );
}
