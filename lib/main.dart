import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'models.dart';
import 'store.dart';
import 'sync_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  final calendarRaw = await rootBundle.loadString('assets/calendars/cn-release-2026-v1.json');
  final calendar = BusinessCalendar.fromJsonString(calendarRaw);
  runApp(QuadrantApp(store: store, calendar: calendar));
}

class QuadrantApp extends StatelessWidget {
  final LocalStore store;
  final BusinessCalendar calendar;
  const QuadrantApp({super.key, required this.store, required this.calendar});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '象限计划',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueGrey,
        visualDensity: VisualDensity.standard,
      ),
      home: HomeShell(store: store, calendar: calendar),
    );
  }
}

class HomeShell extends StatefulWidget {
  final LocalStore store;
  final BusinessCalendar calendar;
  const HomeShell({super.key, required this.store, required this.calendar});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  late final SyncClient sync = SyncClient(widget.store);

  @override
  void dispose() {
    sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TasksPage(store: widget.store, calendar: widget.calendar),
      ReportsPage(store: widget.store, calendar: widget.calendar),
      TagsPage(store: widget.store),
      SettingsPage(store: widget.store, calendar: widget.calendar, sync: sync),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.task_alt), label: Text('任务')),
              NavigationRailDestination(icon: Icon(Icons.grid_view), label: Text('周报')),
              NavigationRailDestination(icon: Icon(Icons.label_outline), label: Text('标签')),
              NavigationRailDestination(icon: Icon(Icons.settings), label: Text('设置')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[index]),
        ],
      ),
    );
  }
}

class TasksPage extends StatefulWidget {
  final LocalStore store;
  final BusinessCalendar calendar;
  const TasksPage({super.key, required this.store, required this.calendar});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool showCompleted = false;
  String? selectedTag;
  bool untagged = false;
  String? selectedTask;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: widget.store.changes,
      builder: (context, _) => FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          widget.store.listTasks(
            includeCompleted: showCompleted,
            tagId: selectedTag,
            untaggedOnly: untagged,
          ),
          widget.store.listTags(),
          widget.store.settings(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final tasks = snapshot.data![0] as List<TaskRecord>;
          final tags = snapshot.data![1] as List<TagRecord>;
          final settings = snapshot.data![2] as AppSettings;
          TaskRecord? selected;
          for (final task in tasks) {
            if (task.id == selectedTask) {
              selected = task;
              break;
            }
          }

          return Row(
            children: [
              SizedBox(
                width: 210,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text('筛选', style: Theme.of(context).textTheme.titleMedium),
                    ListTile(
                      selected: selectedTag == null && !untagged,
                      title: const Text('全部'),
                      onTap: () => setState(() {
                        selectedTag = null;
                        untagged = false;
                      }),
                    ),
                    ListTile(
                      selected: untagged,
                      title: const Text('未分组'),
                      onTap: () => setState(() {
                        selectedTag = null;
                        untagged = true;
                      }),
                    ),
                    ...tags.map(
                      (tag) => ListTile(
                        selected: selectedTag == tag.id,
                        title: Text(tag.name),
                        onTap: () => setState(() {
                          selectedTag = tag.id;
                          untagged = false;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text('任务', style: Theme.of(context).textTheme.headlineSmall),
                          const Spacer(),
                          FilterChip(
                            label: const Text('显示已完成'),
                            selected: showCompleted,
                            onSelected: (value) => setState(() => showCompleted = value),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: () => _editTaskDialog(
                              context,
                              widget.store,
                              widget.calendar,
                              settings,
                              tags,
                              null,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('新增任务'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: tasks.isEmpty
                          ? const Center(child: Text('暂无任务'))
                          : ListView.builder(
                              itemCount: tasks.length,
                              itemBuilder: (context, i) {
                                final task = tasks[i];
                                final urgency = widget.calendar.urgency(task, DateTime.now().toUtc());
                                return ListTile(
                                  selected: selectedTask == task.id,
                                  title: Text(task.title),
                                  subtitle: Text(
                                    urgency == null
                                        ? '紧急性：日历覆盖不完整 · 重要性：${task.importance}'
                                        : '紧急性：$urgency · 重要性：${task.importance}',
                                  ),
                                  trailing: task.status == TaskStatus.completed
                                      ? const Icon(Icons.check_circle)
                                      : null,
                                  onTap: () => setState(() => selectedTask = task.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              if (selected != null)
                SizedBox(
                  width: 340,
                  child: TaskDetail(
                    task: selected,
                    store: widget.store,
                    calendar: widget.calendar,
                    settings: settings,
                    tags: tags,
                    onDeleted: () => setState(() => selectedTask = null),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class TaskDetail extends StatelessWidget {
  final TaskRecord task;
  final LocalStore store;
  final BusinessCalendar calendar;
  final AppSettings settings;
  final List<TagRecord> tags;
  final VoidCallback onDeleted;
  const TaskDetail({
    super.key,
    required this.task,
    required this.store,
    required this.calendar,
    required this.settings,
    required this.tags,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final urgency = calendar.urgency(task, DateTime.now().toUtc());
    final tagNames = tags.where((t) => task.tagIds.contains(t.id)).map((t) => t.name).join('、');
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(task.note.isEmpty ? '无备注' : task.note),
          const SizedBox(height: 16),
          Text('真实坐标：(${urgency ?? '?'}, ${task.importance})'),
          Text('标签：${tagNames.isEmpty ? '未分组' : tagNames}'),
          Text('创建：${task.createdAt.toLocal()}'),
          if (task.completedAt != null) Text('完成：${task.completedAt!.toLocal()}'),
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: () => _editTaskDialog(context, store, calendar, settings, tags, task),
            child: const Text('编辑'),
          ),
          if (task.status == TaskStatus.active)
            FilledButton(
              onPressed: () => store.completeTask(task),
              child: const Text('完成'),
            ),
          OutlinedButton(
            onPressed: () async {
              await store.deleteTask(task);
              onDeleted();
            },
            child: const Text('删除'),
          ),
          const Divider(height: 32),
          Text('事件轨迹', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<TaskEvent>>(
            future: store.taskHistory(task.id),
            builder: (context, snapshot) {
              final events = snapshot.data ?? const <TaskEvent>[];
              return Column(
                children: events
                    .map(
                      (e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.type),
                        subtitle: Text(e.occurredAt.toLocal().toString()),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _editTaskDialog(
  BuildContext context,
  LocalStore store,
  BusinessCalendar calendar,
  AppSettings settings,
  List<TagRecord> tags,
  TaskRecord? existing,
) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  final currentUrgency = existing == null ? 0 : (calendar.urgency(existing, DateTime.now().toUtc()) ?? existing.urgencyAnchor);
  final importance = TextEditingController(text: (existing?.importance ?? 0).toString());
  final urgency = TextEditingController(text: currentUrgency.toString());
  final selectedTags = <String>{...?existing?.tagIds};
  var resetUrgencyAnchor = existing == null;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(existing == null ? '新增任务' : '编辑任务'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: '标题')),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: importance,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '重要性 ${settings.importanceMin}…${settings.importanceMax}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: urgency,
                        enabled: existing == null || resetUrgencyAnchor,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '紧急性 ${settings.urgencyMin}…${settings.urgencyMax}',
                        ),
                      ),
                    ),
                  ],
                ),
                if (existing != null)
                  CheckboxListTile(
                    value: resetUrgencyAnchor,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('重新设置紧急性锚点'),
                    subtitle: const Text('关闭时，编辑标题/重要性不会改变紧急性历史轨迹'),
                    onChanged: (v) => setDialogState(() => resetUrgencyAnchor = v ?? false),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('标签', style: Theme.of(context).textTheme.titleSmall),
                ),
                ...tags.map(
                  (tag) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tag.name),
                    value: selectedTags.contains(tag.id),
                    onChanged: (checked) => setDialogState(() {
                      if (checked == true) {
                        selectedTags.add(tag.id);
                      } else {
                        selectedTags.remove(tag.id);
                      }
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                final imp = int.parse(importance.text.trim());
                final urg = int.parse(urgency.text.trim());
                if (existing == null) {
                  await store.createTask(
                    title: title.text,
                    note: note.text,
                    importance: imp,
                    urgency: urg,
                    tagIds: selectedTags.toList(),
                  );
                } else {
                  await store.editTask(
                    existing,
                    title: title.text,
                    note: note.text,
                    importance: imp,
                    newUrgency: resetUrgencyAnchor ? urg : null,
                    tagIds: selectedTags.toList(),
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

class ReportsPage extends StatefulWidget {
  final LocalStore store;
  final BusinessCalendar calendar;
  const ReportsPage({super.key, required this.store, required this.calendar});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime start = _monday(DateTime.now().toUtc());

  static DateTime _monday(DateTime d) {
    final day = DateTime.utc(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: widget.store.changes,
      builder: (context, _) => FutureBuilder<WeeklySummary>(
        future: widget.store.weeklySummary(widget.calendar, start),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final r = snapshot.data!;
          final heat = r.heatmap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Text('周报', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  IconButton(
                    onPressed: () => setState(() => start = start.subtract(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${r.from.toLocal().toString().split(' ').first} — ${r.to.subtract(const Duration(days: 1)).toLocal().toString().split(' ').first}'),
                  IconButton(
                    onPressed: () => setState(() => start = start.add(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric('新增', r.created),
                  _metric('完成', r.completed),
                  _metric('期末未完成', r.activeAtEnd),
                  _metric('任务日', r.taskDays),
                ],
              ),
              const SizedBox(height: 24),
              Text('坐标热力数据', style: Theme.of(context).textTheme.titleLarge),
              if (heat.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('本周没有可统计的任务日'),
                )
              else
                ...heat.take(40).map(
                      (e) => ListTile(
                        title: Text('紧急性 / 重要性：${e.key}'),
                        trailing: Text('${e.value} 任务日'),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(String label, int value) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Text(label),
              Text('$value', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class TagsPage extends StatelessWidget {
  final LocalStore store;
  const TagsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: store.changes,
      builder: (context, _) => FutureBuilder<List<TagRecord>>(
        future: store.listTags(includeArchived: true),
        builder: (context, snapshot) {
          final tags = snapshot.data ?? const <TagRecord>[];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Text('标签', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () async {
                      final name = await _prompt(context, '新建标签');
                      if (name != null) await store.createTag(name);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('新建'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...tags.map(
                (tag) => ListTile(
                  title: Text(tag.name),
                  subtitle: Text(tag.archived ? '已归档' : '当前'),
                  trailing: tag.archived
                      ? null
                      : Wrap(
                          children: [
                            IconButton(
                              onPressed: () async {
                                final name = await _prompt(context, '重命名标签', tag.name);
                                if (name != null) await store.renameTag(tag, name);
                              },
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              onPressed: () => store.archiveTag(tag),
                              icon: const Icon(Icons.archive),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final LocalStore store;
  final BusinessCalendar calendar;
  final SyncClient sync;
  const SettingsPage({
    super.key,
    required this.store,
    required this.calendar,
    required this.sync,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String message = '';

  void _setMessage(Object value) {
    if (mounted) setState(() => message = value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: widget.store.changes,
      builder: (context, _) => FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          widget.store.settings(),
          widget.store.activeProfile(),
          widget.store.conflictCount(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final settings = snapshot.data![0] as AppSettings;
          final profile = snapshot.data![1] as Map<String, Object?>;
          final conflicts = snapshot.data![2] as int;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: Text('当前空间：${profile['kind'] == 'account' ? '云账号' : '本地'}'),
                  subtitle: Text('profile: ${profile['profile_id']}'),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text('输入范围：重要性 ${settings.importanceMin}…${settings.importanceMax} / 紧急性 ${settings.urgencyMin}…${settings.urgencyMax}'),
                  subtitle: const Text('修改范围只影响后续输入校验，不会裁剪历史真实值'),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text('业务日历：${widget.calendar.version}'),
                  subtitle: Text('覆盖年份：${widget.calendar.coveredYears.join(', ')}；周末和法定休假日不增长紧急性'),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text('备份与恢复'),
                  subtitle: const Text('恢复会创建新的本地 profile；校验失败时不会留下半恢复状态'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () async {
                          try {
                            final backup = await widget.store.exportBackup();
                            final location = await getSaveLocation(
                              suggestedName: 'QuadrantPlanner-backup.json',
                            );
                            if (location == null) return;
                            await File(location.path).writeAsString(
                              const JsonEncoder.withIndent('  ').convert(backup),
                              flush: true,
                            );
                            _setMessage('备份已导出');
                          } catch (e) {
                            _setMessage(e);
                          }
                        },
                        child: const Text('导出'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            final file = await openFile(
                              acceptedTypeGroups: const [
                                XTypeGroup(label: 'JSON', extensions: ['json']),
                              ],
                            );
                            if (file == null) return;
                            final raw = await file.readAsString();
                            await widget.store.restoreBackup(
                              (jsonDecode(raw) as Map).cast<String, Object?>(),
                            );
                            _setMessage('恢复完成，已切换到新的本地空间');
                          } catch (e) {
                            _setMessage(e);
                          }
                        },
                        child: const Text('恢复'),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: Icon(widget.sync.config.configured ? Icons.cloud : Icons.cloud_off),
                  title: Text(widget.sync.config.configured ? '云同步已配置' : '纯本地构建'),
                  subtitle: Text(
                    widget.sync.config.configured
                        ? '邮箱 OTP + revision/CAS + 幂等 outbox + 分页 cursor'
                        : '未提供 SUPABASE_URL / SUPABASE_ANON_KEY，不会发起网络请求',
                  ),
                ),
              ),
              if (widget.sync.config.configured)
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        try {
                          final email = await _prompt(context, '登录邮箱');
                          if (email == null) return;
                          await widget.sync.requestOtp(email);
                          if (!mounted) return;
                          final code = await _prompt(context, '输入邮箱验证码');
                          if (code == null) return;
                          await widget.sync.verifyOtp(email, code);
                          await widget.sync.syncNow();
                          _setMessage('登录并同步完成');
                        } catch (e) {
                          _setMessage(e);
                        }
                      },
                      child: const Text('邮箱 OTP 登录'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await widget.sync.syncNow();
                          _setMessage('同步完成');
                        } catch (e) {
                          _setMessage(e);
                        }
                      },
                      child: const Text('立即同步'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await widget.sync.logout();
                        _setMessage('已退出云账号并返回本地空间');
                      },
                      child: const Text('退出云账号'),
                    ),
                  ],
                ),
              if (conflicts > 0)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text('有 $conflicts 个同步冲突被冻结'),
                    subtitle: const Text('本地修改不会被静默覆盖；冲突数据保存在本机数据库中'),
                  ),
                ),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SelectableText(message),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, [String initial = '']) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
