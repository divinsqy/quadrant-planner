import 'package:flutter/material.dart';

import '../../../domain/reports/report_evidence.dart';

class EvidencePanel extends StatelessWidget {
  final List<ReportEvidenceRef> evidence;
  final ValueChanged<String>? onOpenTask;
  final String storageId;
  const EvidencePanel({
    super.key,
    required this.evidence,
    this.onOpenTask,
    required this.storageId,
  });
  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey(storageId),
    title: const Text('查看依据'),
    children: [
      for (final ref in evidence)
        ListTile(
          title: Text(
            '${switch (ref.kind) {
              'task' => '任务',
              'activity' => '活动',
              'focus' => '专注',
              'note' => '笔记',
              'project' => '项目',
              'milestone' => '里程碑',
              'manual' => '手动记录',
              _ => '计划',
            }} · ${ref.title}',
          ),
          subtitle: Text(
            '${ref.detail}${ref.occurredAt == null ? '' : '\n${ref.occurredAt!.toLocal()}'}',
          ),
          onTap: ref.kind == 'task' && onOpenTask != null
              ? () => onOpenTask!(ref.sourceId)
              : null,
        ),
    ],
  );
}
