import 'package:flutter/material.dart';

import '../application/global_search_controller.dart';

class CommandPalette extends StatefulWidget {
  final GlobalSearchController controller;
  final ValueChanged<GlobalSearchResult> onOpenResult;

  const CommandPalette({
    super.key,
    required this.controller,
    required this.onOpenResult,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant CommandPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
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
    final controller = widget.controller;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              onChanged: controller.search,
              decoration: const InputDecoration(
                hintText: '搜索任务、项目或标签',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            if (controller.isLoading)
              const LinearProgressIndicator(minHeight: 2),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('搜索失败：${controller.error}'),
              ),
            if (!controller.isLoading &&
                controller.error == null &&
                controller.results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('输入关键词开始搜索'),
              ),
            for (final result in controller.results)
              ListTile(
                leading: Icon(
                  result.type == SearchEntityType.task
                      ? Icons.check_circle_outline_rounded
                      : Icons.folder_outlined,
                ),
                title: Text(result.title),
                subtitle: result.subtitle.isEmpty
                    ? null
                    : Text(result.subtitle),
                onTap: () => widget.onOpenResult(result),
              ),
          ],
        ),
      ),
    );
  }
}
