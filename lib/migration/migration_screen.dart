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
    widget.controller.addListener(_onChanged);
    widget.controller.initialize();
  }

  @override
  void didUpdateWidget(MigrationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.controller.phase) {
      case MigrationPhase.ready:
        return widget.readyBuilder(context);
      case MigrationPhase.previewRequired:
        return _MigrationPreview(controller: widget.controller);
      case MigrationPhase.failed:
        return _MigrationFailure(controller: widget.controller);
      case MigrationPhase.checking:
      case MigrationPhase.importing:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
    }
  }
}

class _MigrationPreview extends StatelessWidget {
  final MigrationController controller;

  const _MigrationPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final preview = controller.previewValue!;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '检测到旧版 Quadrant Planner 数据',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Text('任务 ${preview.taskCount}'),
                Text('标签 ${preview.tagCount}'),
                Text('历史事件 ${preview.eventCount}'),
                if (preview.skipped.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '有 ${preview.skipped.length} 条无法读取的数据，将在导入报告中列出。',
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: controller.importLegacy,
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
  final MigrationController controller;

  const _MigrationFailure({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '旧版数据导入失败',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(controller.error?.toString() ?? '未知错误'),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: controller.retry,
                  child: const Text('重试'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: controller.continueWithEmptyV1,
                  child: const Text('继续使用新的空白 v1'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
