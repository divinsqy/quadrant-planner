import 'package:flutter/material.dart';

import 'migration_controller.dart';

class MigrationScreen extends StatefulWidget {
  final MigrationController controller;
  final WidgetBuilder readyBuilder;

  const MigrationScreen({
    super.key,
    required this.controller,
    required this.readyBuilder,
  });

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
    widget.controller.initialize();
  }

  @override
  void didUpdateWidget(covariant MigrationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleChange);
    widget.controller.addListener(_handleChange);
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return switch (controller.stage) {
      MigrationStage.ready => widget.readyBuilder(context),
      MigrationStage.checking || MigrationStage.importing => const Center(
          child: CircularProgressIndicator(),
        ),
      MigrationStage.previewRequired => _MigrationPreview(
          preview: controller.preview!,
          onImport: controller.importLegacy,
        ),
      MigrationStage.failed => _MigrationFailure(
          error: controller.error,
          onRetry: controller.retry,
          onContinue: controller.continueWithEmptyV1,
        ),
    };
  }
}

class _MigrationPreview extends StatelessWidget {
  final LegacyMigrationPreview preview;
  final VoidCallback onImport;

  const _MigrationPreview({
    required this.preview,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '检测到旧版 Quadrant Planner 数据',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text('任务：' + preview.taskCount.toString()),
                Text('标签：' + preview.tagCount.toString()),
                Text('历史事件：' + preview.eventCount.toString()),
                if (preview.skipped.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '有 ' +
                        preview.skipped.length.toString() +
                        ' 项无法解析，将在导入结果中列出。',
                  ),
                ],
                const SizedBox(height: 20),
                const Text('导入不会修改或删除旧版数据库。'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onImport,
                  child: const Text('导入到 v1.0'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MigrationFailure extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  const _MigrationFailure({
    required this.error,
    required this.onRetry,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 40),
              const SizedBox(height: 12),
              Text(
                '旧版数据导入未完成',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(error?.toString() ?? '未知错误'),
              const SizedBox(height: 16),
              const Text('旧版数据库仍保持原样。'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                  OutlinedButton(
                    onPressed: onContinue,
                    child: const Text('继续使用新的空白 v1'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
