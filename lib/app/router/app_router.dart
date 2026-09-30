import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppDestinationConfig {
  final String name;
  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  const AppDestinationConfig({
    required this.name,
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });
}

const appDestinations = <AppDestinationConfig>[
  AppDestinationConfig(
    name: 'dashboard',
    label: 'Dashboard',
    path: '/dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
  ),
  AppDestinationConfig(
    name: 'inbox',
    label: '收集箱',
    path: '/inbox',
    icon: Icons.inbox_outlined,
    selectedIcon: Icons.inbox_rounded,
  ),
  AppDestinationConfig(
    name: 'tasks',
    label: '任务',
    path: '/tasks',
    icon: Icons.check_circle_outline_rounded,
    selectedIcon: Icons.check_circle_rounded,
  ),
  AppDestinationConfig(
    name: 'projects',
    label: '项目',
    path: '/projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder_rounded,
  ),
  AppDestinationConfig(
    name: 'planner',
    label: '规划',
    path: '/planner',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today_rounded,
  ),
  AppDestinationConfig(
    name: 'reports',
    label: '周报',
    path: '/reports',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description_rounded,
  ),
  AppDestinationConfig(
    name: 'settings',
    label: '设置',
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
];

GoRouter createAppRouter({
  required Widget Function(
    BuildContext context,
    AppDestinationConfig destination,
  ) pageBuilder,
}) {
  return GoRouter(
    initialLocation: appDestinations.first.path,
    routes: [
      for (final destination in appDestinations)
        GoRoute(
          name: destination.name,
          path: destination.path,
          builder: (context, state) => pageBuilder(context, destination),
        ),
      GoRoute(
        name: 'taskDetail',
        path: '/tasks/:taskId',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        name: 'projectDetail',
        path: '/projects/:projectId',
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );
}
