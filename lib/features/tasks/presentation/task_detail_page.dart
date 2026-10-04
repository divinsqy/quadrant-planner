import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/tasks/subtask.dart';
import '../../../domain/tasks/task.dart';
import '../../../domain/tasks/task_activity_event.dart';
import '../../projects/data/project_repository.dart';
import '../../reports/data/weekly_note_repository.dart';
import '../../reports/presentation/weekly_note_dialog.dart';
import '../application/task_editor_controller.dart';
import '../data/task_activity_repository.dart';
import '../data/task_relations_repository.dart';
import '../data/task_repository.dart';
import 'task_editor.dart';

class TaskDetailPage extends StatelessWidget {
  final String taskId;
  final TaskRepository tasks;
  final TaskEditorController editor;
  final TaskActivityRepository activity;
  final TaskRelationsRepository? relations;
  final ProjectRepository? projects;
  final ValueChanged<String>? onStartFocus;
  final WeeklyNoteRepository? weeklyNotes;
  final DateTime Function()? noteClock;

  const TaskDetailPage({
    super.key,
    required this.taskId,
    required this.tasks,
    required this.editor,
    required this.activity,
    this.relations,
    this.projects,
    this.onStartFocus,
    this.weeklyNotes,
    this.noteClock,
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<Task?>(
    stream: tasks.watchTask(taskId),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(body: Center(child: Text('任务读取失败：${snapshot.error}')));
      }
      final task = snapshot.data;
      if (task == null || task.deletedAt != null) {
        return Scaffold(
          body: Center(
            child: snapshot.connectionState == ConnectionState.waiting
                ? const CircularProgressIndicator()
                : const Text('任务不存在'),
          ),
        );
      }
      final repository = relations ?? tasks.relations;
      return DefaultTabController(
        length: 4,
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : null,
        child: Scaffold(
          appBar: AppBar(
            title: Text(task.title),
            actions: [
              if (weeklyNotes != null)
                IconButton(
                  tooltip: '记录本周笔记',
                  icon: const Icon(Icons.note_add_outlined),
                  onPressed: () => showWeeklyNoteDialog(
                    context,
                    notes: weeklyNotes!,
                    weekStart: (noteClock ?? DateTime.now)(),
                    taskId: task.id,
                  ),
                ),
              if (onStartFocus != null &&
                  (task.status.name == 'planned' ||
                      task.status.name == 'inProgress'))
                IconButton(
                  tooltip: '开始专注',
                  onPressed: () => onStartFocus!(task.id),
                  icon: const Icon(Icons.play_arrow),
                ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Subtasks'),
                Tab(text: 'Dependencies'),
                Tab(text: 'Activity'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: TaskEditor(
                  task: task,
                  controller: editor,
                  projects: projects,
                ),
              ),
              _SubtasksTab(
                key: ValueKey('subtasks-${task.id}'),
                taskId: task.id,
                relations: repository,
              ),
              _DependenciesTab(
                key: ValueKey('dependencies-${task.id}'),
                taskId: task.id,
                relations: repository,
                tasks: tasks,
              ),
              _ActivityTab(
                key: ValueKey('activity-${task.id}'),
                taskId: task.id,
                activity: activity,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SubtasksTab extends StatefulWidget {
  final String taskId;
  final TaskRelationsRepository relations;
  const _SubtasksTab({
    super.key,
    required this.taskId,
    required this.relations,
  });
  @override
  State<_SubtasksTab> createState() => _SubtasksTabState();
}

class _SubtasksTabState extends State<_SubtasksTab> {
  final _title = TextEditingController();
  late final _items = widget.relations.watchSubtasks(widget.taskId);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = '操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Subtask item) async {
    var title = item.title;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑子任务'),
        content: TextFormField(
          initialValue: title,
          onChanged: (value) => title = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: '子任务标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null) {
      await _run(() => widget.relations.updateSubtask(item.id, title: value));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '子任务标题'),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('添加子任务'),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      Expanded(
        child: StreamBuilder<List<Subtask>>(
          stream: _items,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('读取失败：${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) return const Center(child: Text('暂无子任务'));
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Checkbox(
                    value: item.completed,
                    onChanged: _busy
                        ? null
                        : (value) => _run(
                            () => widget.relations.updateSubtask(
                              item.id,
                              completed: value,
                            ),
                          ),
                  ),
                  title: Text(
                    item.title,
                    style: item.completed
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: '编辑子任务',
                        onPressed: _busy ? null : () => _rename(item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: '删除子任务',
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => widget.relations.deleteSubtask(item.id),
                              ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  Future<void> _add() => _run(() async {
    await widget.relations.addSubtask(widget.taskId, _title.text);
    _title.clear();
  });
}

class _DependenciesTab extends StatefulWidget {
  final String taskId;
  final TaskRelationsRepository relations;
  final TaskRepository tasks;
  const _DependenciesTab({
    super.key,
    required this.taskId,
    required this.relations,
    required this.tasks,
  });
  @override
  State<_DependenciesTab> createState() => _DependenciesTabState();
}

class _DependenciesTabState extends State<_DependenciesTab> {
  late final _dependencies = widget.relations.watchDependencies(widget.taskId);
  late final _tasks = widget.tasks.watchTasks();
  String? _selected;
  String? _error;
  bool _busy = false;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = '操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<TaskDependencyState>>(
    stream: _dependencies,
    builder: (context, snapshot) {
      final dependencies = snapshot.data ?? const <TaskDependencyState>[];
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StreamBuilder<List<Task>>(
                  stream: _tasks,
                  builder: (context, snapshot) {
                    final candidates = (snapshot.data ?? const <Task>[])
                        .where(
                          (task) =>
                              task.id != widget.taskId &&
                              !dependencies.any(
                                (d) => d.dependency.dependsOnTaskId == task.id,
                              ),
                        )
                        .toList();
                    final selected = candidates.any((t) => t.id == _selected)
                        ? _selected
                        : null;
                    return DropdownButtonFormField<String>(
                      key: ValueKey(
                        'dependency-$selected-${candidates.length}',
                      ),
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '前置任务'),
                      items: [
                        for (final task in candidates)
                          DropdownMenuItem(
                            value: task.id,
                            child: Text(
                              task.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _selected = value),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy || _selected == null
                        ? null
                        : () => _run(() async {
                            await widget.relations.addDependency(
                              widget.taskId,
                              _selected!,
                            );
                            if (mounted) setState(() => _selected = null);
                          }),
                    icon: const Icon(Icons.add_link),
                    label: const Text('添加依赖'),
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: snapshot.hasError
                ? Center(child: Text('读取失败：${snapshot.error}'))
                : dependencies.isEmpty
                ? const Center(child: Text('暂无依赖关系'))
                : ListView.builder(
                    itemCount: dependencies.length,
                    itemBuilder: (context, index) {
                      final dependency = dependencies[index];
                      return ListTile(
                        leading: Icon(
                          dependency.satisfied
                              ? Icons.check_circle_outline
                              : Icons.hourglass_empty,
                        ),
                        title: Text(dependency.title),
                        subtitle: Text(dependency.blockingReason ?? '前置依赖已满足'),
                        trailing: IconButton(
                          tooltip: '移除依赖',
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => widget.relations.removeDependency(
                                    dependency.dependency.id,
                                  ),
                                ),
                          icon: const Icon(Icons.link_off),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class _ActivityTab extends StatefulWidget {
  final String taskId;
  final TaskActivityRepository activity;
  const _ActivityTab({super.key, required this.taskId, required this.activity});
  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  static const _pageSize = 50;
  final List<TaskActivityEvent> _events = [];
  StreamSubscription<List<TaskActivityEvent>>? _subscription;
  bool _loading = true;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.activity
        .watchRecent(widget.taskId, limit: _pageSize)
        .listen(
          (recent) {
            if (!mounted) return;
            final existing = {for (final event in _events) event.id: event};
            for (final event in recent) {
              existing[event.id] = event;
            }
            setState(() {
              _events
                ..clear()
                ..addAll(existing.values);
              _sort();
              _loading = false;
              if (_events.length <= _pageSize) {
                _hasMore = recent.length == _pageSize;
              }
            });
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _error = '读取失败：$error';
                _loading = false;
              });
            }
          },
        );
  }

  void _sort() => _events.sort((a, b) {
    final date = b.occurredAt.compareTo(a.occurredAt);
    return date == 0 ? b.id.compareTo(a.id) : date;
  });

  Future<void> _more() async {
    if (_loading || !_hasMore || _events.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cursor = _events.last;
      final page = await widget.activity.fetchPage(
        widget.taskId,
        limit: _pageSize,
        before: cursor.occurredAt,
        beforeId: cursor.id,
      );
      if (!mounted) return;
      setState(() {
        final ids = _events.map((e) => e.id).toSet();
        _events.addAll(page.where((e) => !ids.contains(e.id)));
        _sort();
        _hasMore = page.length == _pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(24),
    itemCount: _events.length + 1,
    itemBuilder: (context, index) {
      if (index == _events.length) {
        return Column(
          children: [
            if (_error != null) Text(_error!),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading && _events.isEmpty) const Text('暂无活动记录'),
            if (!_loading && _hasMore && _events.isNotEmpty)
              TextButton(onPressed: _more, child: const Text('加载更多活动')),
          ],
        );
      }
      final event = _events[index];
      return ListTile(
        leading: const Icon(Icons.history),
        title: Text(switch (event.type) {
          'created' => '任务创建',
          'completed' => '任务完成',
          'task_updated' => '任务更新',
          'dependency_added' => '添加依赖',
          'dependency_removed' => '移除依赖',
          'subtask_added' => '添加子任务',
          'subtask_updated' => '更新子任务',
          'subtask_deleted' => '删除子任务',
          'focus_started' => '开始专注',
          'focus_paused' => '暂停专注',
          'focus_resumed' => '继续专注',
          'focus_completed' => '专注完成',
          'focus_blocked' => '专注阻塞',
          _ => event.type,
        }),
        subtitle: Text('${event.occurredAt.toLocal()}${_changes(event)}'),
      );
    },
  );

  String _changes(TaskActivityEvent event) {
    final seconds = event.payload['actualSeconds'];
    if (event.type.startsWith('focus_') && seconds is num) {
      return '\n实际用时 ${(seconds / 60).toStringAsFixed(1)} 分钟';
    }
    final changes = event.payload['changes'];
    if (changes is! Map) return '';
    return '\n${changes.entries.map((entry) {
      final value = entry.value;
      return value is Map ? '${entry.key}: ${value['before']} → ${value['after']}' : entry.key;
    }).join('\n')}';
  }
}
