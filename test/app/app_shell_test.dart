import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/router/app_router.dart';
import 'package:quadrant_planner/app/shell/app_shell.dart';
import 'package:quadrant_planner/app/theme/app_theme.dart';

void main() {
  test('app destinations define Dashboard as default and expose seven sections', () {
    expect(appDestinations, hasLength(7));
    expect(appDestinations.first.path, '/dashboard');
    expect(appDestinations.map((item) => item.label), [
      'Dashboard',
      '收集箱',
      '任务',
      '项目',
      '规划',
      '周报',
      '设置',
    ]);

    final router = createAppRouter(
      pageBuilder: (context, destination) => Text(destination.label),
    );
    expect(router.routeInformationProvider.value.uri.path, '/dashboard');
    router.dispose();
  });

  test('light and dark themes expose the requested brightness', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });

  testWidgets('shell supports keyboard navigation and global search shortcut', (
    tester,
  ) async {
    var selected = -1;
    var searchCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          selectedIndex: 0,
          onDestinationSelected: (index) => selected = index,
          onOpenSearch: () => searchCalls += 1,
          child: const Text('Dashboard body'),
        ),
      ),
    );

    expect(find.text('Dashboard body'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(selected, 6);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(searchCalls, 1);
  });
}
