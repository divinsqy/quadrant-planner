import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/export/csv_task_exporter.dart';
import '../../../core/export/json_data_exporter.dart';

abstract interface class BackupFileGateway {
  Future<String?> pickBackup();
  Future<bool> save(String filename, Uint8List bytes);
}

class DesktopBackupFileGateway implements BackupFileGateway {
  @override
  Future<String?> pickBackup() async => (await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Quadrant 备份',
        extensions: ['qpb'],
        uniformTypeIdentifiers: ['public.data'],
      ),
    ],
  ))?.path;
  @override
  Future<bool> save(String filename, Uint8List bytes) async {
    final extension = filename.split('.').last;
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [
        XTypeGroup(
          label: '用户数据',
          extensions: [extension],
          uniformTypeIdentifiers: [
            extension == 'json'
                ? 'public.json'
                : extension == 'csv'
                ? 'public.comma-separated-values-text'
                : 'public.data',
          ],
        ),
      ],
    );
    if (location == null) return false;
    await XFile.fromData(bytes, name: filename).saveTo(location.path);
    return true;
  }
}

class BackupRestoreSection extends StatefulWidget {
  final BackupService service;
  final BackupFileGateway? files;
  final Future<T> Function<T>(Future<T> Function())? pauseSync;
  const BackupRestoreSection({
    super.key,
    required this.service,
    this.files,
    this.pauseSync,
  });
  @override
  State<BackupRestoreSection> createState() => _BackupRestoreSectionState();
}

class _BackupRestoreSectionState extends State<BackupRestoreSection> {
  late final _files = widget.files ?? DesktopBackupFileGateway();
  bool _busy = false, _includeDeleted = true;
  String? _message;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is BackupFailure && error.snapshotPath != null
              ? '恢复失败，本地数据未更改。恢复前快照：${error.snapshotPath}'
              : '操作失败，原有数据已保留。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String extension) async {
    final bytes = extension == 'qpb'
        ? await widget.service.bytes()
        : Uint8List.fromList(
            utf8.encode(
              extension == 'json'
                  ? await JsonDataExporter(widget.service.db).render()
                  : await CsvTaskExporter(widget.service.db)
                        .render(includeDeleted: _includeDeleted),
            ),
          );
    final saved = await _files.save(
      'quadrant-${DateTime.now().toUtc().millisecondsSinceEpoch}.$extension',
      bytes,
    );
    if (saved && mounted) setState(() => _message = '已导出 $extension');
  }

  Future<void> _restore() async {
    final path = await _files.pickBackup();
    if (path == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从备份恢复'),
        content: const Text(
          '将替换此设备的任务、项目、计划、周报和设置。恢复前会先保存独立快照，云同步将暂停，需手动重新开启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建快照并恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final snapshot = widget.pauseSync == null
        ? await widget.service.restoreBackup(path)
        : await widget.pauseSync!(() => widget.service.restoreBackup(path));
    if (mounted) setState(() => _message = '恢复完成，云同步已暂停。恢复前快照：$snapshot');
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('备份与导出', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text('.qpb 包含本地用户数据、设置、样式及历史记录。备份独立于云同步，账户凭据保存在系统安全存储。'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _busy ? null : () => _run(() => _export('qpb')),
            child: const Text('创建 .qpb 备份'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(_restore),
            child: const Text('恢复 .qpb 备份'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() => _export('json')),
            child: const Text('导出 JSON'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() => _export('csv')),
            child: const Text('导出 CSV'),
          ),
        ],
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('CSV 包含已删除任务'),
        value: _includeDeleted,
        onChanged: _busy
            ? null
            : (value) => setState(() => _includeDeleted = value!),
      ),
      if (_message != null) SelectableText(_message!),
    ],
  );
}
