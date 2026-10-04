import 'package:flutter/material.dart';

import '../../../domain/projects/project.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_status.dart';
import '../../projects/data/project_repository.dart';
import '../application/task_editor_controller.dart';
import '../application/tasks_library_controller.dart';
import '../data/task_activity_repository.dart';
import '../data/task_repository.dart';
import 'task_editor.dart';
import 'task_preview_drawer.dart';

class TasksPage extends StatefulWidget {
  final TaskRepository tasks;
  final TaskEditorController editor;
  final TaskActivityRepository activity;
  final ValueChanged<String>? onOpenTask;
  final ProjectRepository? projects;
  final TasksLibraryController? controller;
  final String? initialTagId;

  const TasksPage({
    super.key,
    required this.tasks,
    required this.editor,
    required this.activity,
    this.onOpenTask,
    this.projects,
    this.controller,
    this.initialTagId,
  });
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final TasksLibraryController _library =
      widget.controller ??
      TasksLibraryController(
        tasks: widget.tasks,
        initialTagId: widget.initialTagId,
      );
  final _filtersScroll = ScrollController();
  late final _search = TextEditingController(text: _library.state.query);
  late final _scroll = ScrollController(
    initialScrollOffset: _library.state.scrollOffset,
  );
  late Stream<List<Task>> _items;
  late final _projects = widget.projects?.watchAll();

  @override
  void initState() {
    super.initState();
    if (widget.initialTagId != null) {
      _library.setFilters(tagId: widget.initialTagId);
    }
    _items = _library.watchTasks();
    _library.addListener(_changed);
    _scroll.addListener(_scrollChanged);
  }

  void _scrollChanged() => _library.updateScrollOffset(_scroll.offset);
  void _changed() {
    if (!mounted) return;
    if (_search.text != _library.state.query) {
      _search.text = _library.state.query;
    }
    setState(() => _items = _library.watchTasks());
  }

  @override
  void didUpdateWidget(covariant TasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTagId != widget.initialTagId) {
      _library.setFilters(tagId: widget.initialTagId);
    }
  }

  @override
  void dispose() {
    _library.removeListener(_changed);
    _search.dispose();
    _filtersScroll.dispose();
    _scroll.dispose();
    if (widget.controller == null) _library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('任务')),
    body: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 0.45,
            ),
            child: Scrollbar(
              controller: _filtersScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('tasks-filters'),
                controller: _filtersScroll,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          labelText: '搜索任务',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => _library.setFilters(query: value),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('全部状态'),
                            selected: _library.state.statuses.isEmpty,
                            onSelected: (_) =>
                                _library.setFilters(statuses: {}),
                          ),
                          for (final status in TaskStatus.values)
                            FilterChip(
                              label: Text(taskStatusLabel(status)),
                              selected: _library.state.statuses.contains(
                                status,
                              ),
                              onSelected: (selected) {
                                final statuses = {..._library.state.statuses};
                                selected
                                    ? statuses.add(status)
                                    : statuses.remove(status);
                                _library.setFilters(statuses: statuses);
                              },
                            ),
                          if (_library.state.tagId != null)
                            InputChip(
                              label: const Text('标签筛选'),
                              onDeleted: () => _library.setFilters(tagId: null),
                            ),
                        ],
                      ),
                      if (_projects != null)
                        SizedBox(
                          width: 280,
                          child: StreamBuilder<List<Project>>(
                            stream: _projects,
                            builder: (context, snapshot) {
                              final projects =
                                  snapshot.data ?? const <Project>[];
                              final id = _library.state.projectId;
                              return DropdownButtonFormField<String>(
                                key: ValueKey(id),
                                initialValue: id ?? '',
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '项目筛选',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('全部项目'),
                                  ),
                                  for (final project in projects)
                                    DropdownMenuItem(
                                      value: project.id,
                                      child: Text(project.name),
                                    ),
                                  if (id != null &&
                                      !projects.any((p) => p.id == id))
                                    DropdownMenuItem(
                                      value: id,
                                      child: const Text('当前项目'),
                                    ),
                                ],
                                onChanged: (value) => _library.setFilters(
                                  projectId: value == '' ? null : value,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Task>>(
              stream: _items,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('任务读取失败：${snapshot.error}'));
                }
                final items = snapshot.data ?? const <Task>[];
                Task? selected;
                for (final task in items) {
                  if (task.id == _library.state.selectedTaskId) {
                    selected = task;
                    break;
                  }
                }
                Widget list() => items.isEmpty
                    ? const Center(child: Text('暂无匹配任务'))
                    : ListView.separated(
                        key: const PageStorageKey('tasks-library-list'),
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final task = items[index];
                          return ListTile(
                            selected: task.id == _library.state.selectedTaskId,
                            title: Text(task.title),
                            subtitle: Text(
                              '${taskStatusLabel(task.status)} · 重要性 ${task.importance} · 基础紧急性 ${task.baseUrgency}',
                            ),
                            onTap: () => _library.selectTask(task.id),
                            onLongPress: widget.onOpenTask == null
                                ? null
                                : () => widget.onOpenTask!(task.id),
                            trailing: widget.onOpenTask == null
                                ? null
                                : IconButton(
                                    tooltip: '打开完整详情',
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: () =>
                                        widget.onOpenTask!(task.id),
                                  ),
                          );
                        },
                      );
                Widget preview(Task task) => TaskPreviewDrawer(
                  key: ValueKey(task.id),
                  task: task,
                  controller: widget.editor,
                  projects: widget.projects,
                  onClose: () => _library.selectTask(null),
                  onOpenDetail: widget.onOpenTask == null
                      ? null
                      : () => widget.onOpenTask!(task.id),
                );
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow =
                        constraints.maxWidth < 800 ||
                        MediaQuery.textScalerOf(context).scale(14) > 21;
                    if (narrow && selected != null) return preview(selected);
                    return Row(
                      children: [
                        Expanded(child: list()),
                        if (selected != null) ...[
                          const VerticalDivider(width: 1),
                          SizedBox(width: 360, child: preview(selected)),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
