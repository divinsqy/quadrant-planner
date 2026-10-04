import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/inbox/presentation/inbox_page.dart';
import '../features/inbox/presentation/quick_capture.dart';
import '../features/projects/presentation/project_detail_page.dart';
import '../features/projects/presentation/projects_page.dart';
import '../features/search/application/global_search_controller.dart';
import '../features/search/presentation/command_palette.dart';
import '../features/settings/presentation/profile_settings.dart';
import '../features/tasks/presentation/task_detail_page.dart';
import '../features/tasks/presentation/tasks_page.dart';
import 'router/app_router.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';
import 'workspace_providers.dart';
import '../features/focus/presentation/focus_page.dart';
import '../features/planner/presentation/planner_page.dart';
import '../features/settings/presentation/work_schedule_settings.dart';
import '../features/settings/presentation/sync_center.dart';
import '../features/settings/presentation/backup_restore_section.dart';
import '../features/settings/presentation/trash_section.dart';
import '../features/reports/presentation/reports_page.dart';

class DesktopWorkspace extends ConsumerStatefulWidget {
  const DesktopWorkspace({super.key});

  @override
  ConsumerState<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends ConsumerState<DesktopWorkspace> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _themeMode = ValueNotifier(ThemeMode.system);
  bool _searchOpen = false;
  bool _captureOpen = false;
  bool _startingFocus = false;
  @override
  void initState() {
    super.initState();
    ref.read(focusControllerProvider).watch();
    ref.read(focusControllerProvider).recover();
    ref.read(syncCoordinatorProvider).start();
  }

  late final GoRouter _router = createAppRouter(
    navigatorKey: _navigatorKey,
    pageBuilder: _page,
    shellBuilder: (context, shell) => AppShell(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (index) =>
          _router.goNamed(appDestinations[index].name),
      onOpenSearch: _openSearch,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: SyncStatusBadge(
              coordinator: ref.read(syncCoordinatorProvider),
              onOpen: () => _router.goNamed('settings'),
            ),
          ),
          AnimatedBuilder(
            animation: ref.read(focusControllerProvider),
            builder: (context, _) =>
                ref.read(focusControllerProvider).session?.isActive ?? false
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('有未结束的专注会话'),
                        TextButton(
                          onPressed: () => _router.pushNamed('focus'),
                          child: const Text('恢复专注'),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(child: shell),
        ],
      ),
    ),
    taskDetailBuilder: (context, id) => TaskDetailPage(
      taskId: id,
      tasks: ref.read(taskRepositoryProvider),
      editor: ref.read(taskEditorProvider),
      activity: ref.read(taskActivityProvider),
      relations: ref.read(taskRelationsProvider),
      projects: ref.read(projectRepositoryProvider),
      onStartFocus: (id) => _startFocus(id),
      weeklyNotes: ref.read(weeklyNoteRepositoryProvider),
    ),
    projectDetailBuilder: (context, id) => ProjectDetailPage(
      projectId: id,
      projects: ref.read(projectRepositoryProvider),
      tasks: ref.read(taskRepositoryProvider),
      onOpenTask: _openTask,
      onShowQuadrant: (projectId) {
        ref.read(dashboardControllerProvider).filterProject(projectId);
        _router.goNamed('dashboard');
      },
    ),
    focusBuilder: (context) => FocusPage(
      controller: ref.read(focusControllerProvider),
      tasks: ref.read(taskRepositoryProvider),
      onShowPlanner: () => _router.goNamed('planner'),
      weeklyNotes: ref.read(weeklyNoteRepositoryProvider),
    ),
  );

  void _openTask(String id) =>
      _router.pushNamed('taskDetail', pathParameters: {'taskId': id});
  void _openProject(String id) =>
      _router.pushNamed('projectDetail', pathParameters: {'projectId': id});

  Future<void> _startFocus(String id, {String? planBlockId}) async {
    if (_startingFocus) return;
    _startingFocus = true;
    try {
      final focus = ref.read(focusControllerProvider);
      await focus.recover();
      if (!mounted) return;
      if (focus.session?.isActive ?? false) {
        if (focus.session!.taskId == id) {
          _router.pushNamed('focus');
          return;
        }
        final dialogContext = _navigatorKey.currentContext;
        if (dialogContext == null || !dialogContext.mounted) return;
        await showDialog<void>(
          context: dialogContext,
          builder: (ctx) => AlertDialog(
            title: const Text('已有专注会话'),
            content: const Text('请先完成或标记阻塞当前会话，再开始另一个任务。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _router.pushNamed('focus');
                },
                child: const Text('打开当前专注'),
              ),
            ],
          ),
        );
      } else {
        await focus.start(id, planBlockId: planBlockId);
        if (mounted) _router.pushNamed('focus');
      }
    } catch (e) {
      final context = _navigatorKey.currentContext;
      if (mounted && context != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法开始专注：$e')));
      }
    } finally {
      _startingFocus = false;
    }
  }

  Widget _page(BuildContext context, AppDestinationConfig destination) {
    final tasks = ref.read(taskRepositoryProvider);
    final editor = ref.read(taskEditorProvider);
    final projects = ref.read(projectRepositoryProvider);
    return switch (destination.name) {
      'dashboard' => DashboardPage(
        controller: ref.read(dashboardControllerProvider),
        taskRepository: tasks,
        taskEditor: editor,
        projects: projects,
        activity: ref.read(taskActivityProvider),
        onOpenSearch: _openSearch,
        onOpenTask: _openTask,
        onStartFocus: (id) => _startFocus(id),
      ),
      'inbox' => InboxPage(
        tasks: tasks,
        editor: editor,
        projects: projects,
        onOpenTask: _openTask,
      ),
      'tasks' => TasksPage(
        tasks: tasks,
        editor: editor,
        activity: ref.read(taskActivityProvider),
        projects: projects,
        controller: ref.read(tasksLibraryControllerProvider),
        onOpenTask: _openTask,
      ),
      'projects' => ProjectsPage(
        projects: projects,
        tasks: tasks,
        onOpenProject: _openProject,
      ),
      'settings' => ValueListenableBuilder(
        valueListenable: _themeMode,
        builder: (context, mode, _) => _SettingsPage(
          preferences: ProfileSettings(
            preferences: ref.read(preferencesRepositoryProvider),
          ),
          workSchedule: WorkScheduleSettings(
            schedules: ref.read(workScheduleRepositoryProvider),
          ),
          sync: SyncCenter(coordinator: ref.read(syncCoordinatorProvider)),
          backup: BackupRestoreSection(
            service: ref.read(backupServiceProvider),
            pauseSync: ref.read(syncCoordinatorProvider).withSyncPaused,
          ),
          trash: TrashSection(repository: ref.read(trashRepositoryProvider)),
          themeMode: mode,
          onThemeChanged: (mode) => _themeMode.value = mode,
        ),
      ),
      'planner' => PlannerPage(
        controller: ref.read(plannerControllerProvider),
        onOpenTask: _openTask,
        onStartFocus: (id, blockId) => _startFocus(id, planBlockId: blockId),
      ),
      'reports' => ReportsPage(
        controller: ref.read(reportsControllerProvider),
        onOpenTask: _openTask,
      ),
      _ => throw StateError('Unknown workspace destination'),
    };
  }

  Future<void> _openCapture() async {
    final context = _navigatorKey.currentContext;
    if (_captureOpen || context == null) return;
    _captureOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('快速记录'),
          content: SizedBox(
            width: 560,
            child: QuickCapture(
              taskRepository: ref.read(taskRepositoryProvider),
              autofocus: true,
              onCreated: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    } finally {
      _captureOpen = false;
    }
  }

  Future<void> _replan() async {
    try {
      await ref.read(plannerControllerProvider).replan();
    } catch (error) {
      final context = _navigatorKey.currentContext;
      if (mounted && context != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重新规划失败：$error')));
      }
    }
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    _searchOpen = true;
    final controller = ref.read(globalSearchControllerProvider);
    await controller.search('');
    if (!mounted || !context.mounted) {
      _searchOpen = false;
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SingleChildScrollView(
          child: CommandPalette(
            controller: controller,
            onOpenResult: (result) {
              Navigator.of(dialogContext).pop();
              switch (result.type) {
                case SearchEntityType.task:
                  _openTask(result.id);
                case SearchEntityType.project:
                  _openProject(result.id);
                case SearchEntityType.tag:
                  ref
                      .read(tasksLibraryControllerProvider)
                      .setFilters(tagId: result.id);
                  _router.goNamed('tasks');
              }
            },
            onNavigate: (name) {
              Navigator.of(dialogContext).pop();
              _router.goNamed(name);
            },
          ),
        ),
      ),
    );
    _searchOpen = false;
  }

  @override
  void dispose() {
    _router.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _themeMode,
    builder: (context, mode, _) => MaterialApp.router(
      title: 'Quadrant Planner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      routerConfig: _router,
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _openCapture,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
              _openCapture,
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            control: true,
            shift: true,
          ): _replan,
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            meta: true,
            shift: true,
          ): _replan,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_router.canPop()) _router.pop();
          },
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              _openSearch,
          for (var index = 0; index < appDestinations.length; index++)
            SingleActivator(
              [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
                LogicalKeyboardKey.digit5,
                LogicalKeyboardKey.digit6,
                LogicalKeyboardKey.digit7,
              ][index],
              control: true,
            ): () =>
                _router.goNamed(appDestinations[index].name),
          for (var index = 0; index < appDestinations.length; index++)
            SingleActivator(
              [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
                LogicalKeyboardKey.digit5,
                LogicalKeyboardKey.digit6,
                LogicalKeyboardKey.digit7,
              ][index],
              meta: true,
            ): () =>
                _router.goNamed(appDestinations[index].name),
        },
        child: Focus(autofocus: true, child: child!),
      ),
    ),
  );
}

class _SettingsPage extends StatelessWidget {
  final Widget preferences;
  final Widget workSchedule;
  final Widget sync, backup, trash;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  const _SettingsPage({
    required this.preferences,
    required this.workSchedule,
    required this.sync,
    required this.backup,
    required this.trash,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        preferences,
        const SizedBox(height: 32),
        Text('外观', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final mode in ThemeMode.values)
              ChoiceChip(
                label: Text(switch (mode) {
                  ThemeMode.system => '跟随系统',
                  ThemeMode.light => '浅色',
                  ThemeMode.dark => '深色',
                }),
                selected: mode == themeMode,
                onSelected: (_) => onThemeChanged(mode),
              ),
          ],
        ),
        const SizedBox(height: 32),
        workSchedule,
        const SizedBox(height: 32),
        sync,
        const SizedBox(height: 32),
        backup,
        const SizedBox(height: 32),
        trash,
        const SizedBox(height: 8),
        const Text('数据保存在此设备，无需登录。'),
      ],
    ),
  );
}
