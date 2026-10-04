import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/conflict_repository.dart';
import '../../../core/sync/field_merge.dart';

class SyncConflictsPage extends StatelessWidget {
  final ConflictRepository repository;
  const SyncConflictsPage({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('冲突中心')),
    body: StreamBuilder<List<SyncConflictRow>>(
      stream: repository.watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('没有未解决的冲突'));
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final conflict in snapshot.data!)
              _ConflictCard(
                key: ValueKey(conflict.id),
                conflict: conflict,
                repository: repository,
              ),
          ],
        );
      },
    ),
  );
}

class _ConflictCard extends StatefulWidget {
  final SyncConflictRow conflict;
  final ConflictRepository repository;
  const _ConflictCard({
    super.key,
    required this.conflict,
    required this.repository,
  });
  @override
  State<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<_ConflictCard> {
  late final _text = TextEditingController(
    text: jsonDecode(widget.conflict.localJson) is String
        ? jsonDecode(widget.conflict.localJson) as String
        : '',
  );
  bool _busy = false;
  String? _error;
  Future<void> _resolve(ConflictChoice choice) async {
    setState(() => _busy = true);
    try {
      await widget.repository.resolve(
        widget.conflict.id,
        choice,
        mergedText: choice == ConflictChoice.merged ? _text.text : null,
      );
    } catch (_) {
      if (mounted) setState(() => _error = '无法保存此选择，请检查引用关系或文本格式。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conflict;
    final local = jsonDecode(c.localJson), remote = jsonDecode(c.remoteJson);
    String choiceLabel(Object? value, String label) =>
        c.field == '_deletion' &&
            value is Map &&
            !isDeleted(Map<String, Object?>.from(value))
        ? '恢复$label版本'
        : '保留$label';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.entityKind} · ${c.entityId} · ${c.field}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SelectableText('本地：${local is String ? local : jsonEncode(local)}'),
            const SizedBox(height: 8),
            SelectableText(
              '远端：${remote is String ? remote : jsonEncode(remote)}',
            ),
            if (c.field == '_deletion')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('删除保护已生效。选择恢复版本会明确恢复这条记录。'),
              ),
            if (c.field == '_invariant')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('远端时段与当前日历或计划重叠。保留本地可撤销此远端变更；采用远端前请先调整重叠时段。'),
              ),
            if (local is String && remote is String)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: '合并文本'),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _resolve(ConflictChoice.local),
                  child: Text(choiceLabel(local, '本地')),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _resolve(ConflictChoice.remote),
                  child: Text(choiceLabel(remote, '远端')),
                ),
                if (local is String && remote is String)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _resolve(ConflictChoice.merged),
                    child: const Text('保存合并文本'),
                  ),
              ],
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    );
  }
}
