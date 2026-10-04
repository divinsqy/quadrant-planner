import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../router/app_router.dart';
import '../theme/app_tokens.dart';

class AppShell extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenSearch;
  final Widget child;

  const AppShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenSearch,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          onOpenSearch,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onOpenSearch,
    };

    for (var index = 0; index < appDestinations.length; index += 1) {
      final key = _digitKey(index + 1);
      bindings[SingleActivator(key, control: true)] = () =>
          onDestinationSelected(index);
      bindings[SingleActivator(key, meta: true)] = () =>
          onDestinationSelected(index);
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Scaffold(
                body: child,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: [
                    for (final destination in appDestinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      ),
                  ],
                ),
              );
            }

            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    scrollable: true,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -0.86,
                    leading: Padding(
                      padding: const EdgeInsets.only(
                        top: AppTokens.space1,
                        bottom: AppTokens.space2,
                      ),
                      child: IconButton(
                        tooltip: '搜索',
                        onPressed: onOpenSearch,
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    destinations: [
                      for (final destination in appDestinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  Expanded(child: child),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  LogicalKeyboardKey _digitKey(int value) {
    return switch (value) {
      1 => LogicalKeyboardKey.digit1,
      2 => LogicalKeyboardKey.digit2,
      3 => LogicalKeyboardKey.digit3,
      4 => LogicalKeyboardKey.digit4,
      5 => LogicalKeyboardKey.digit5,
      6 => LogicalKeyboardKey.digit6,
      7 => LogicalKeyboardKey.digit7,
      _ => throw ArgumentError.value(value, 'value'),
    };
  }
}
