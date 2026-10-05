import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/features/inbox/presentation/inbox_page.dart';
import 'package:quadrant_planner/features/tasks/presentation/tasks_page.dart';
import 'package:quadrant_planner/features/projects/presentation/projects_page.dart';
import 'package:quadrant_planner/features/planner/presentation/planner_page.dart';
import 'package:quadrant_planner/features/reports/presentation/reports_page.dart';
import 'package:quadrant_planner/features/settings/presentation/profile_settings.dart';
import 'package:quadrant_planner/migration/migration_controller.dart';

class _NoMigration implements MigrationGateway {
  @override
  Future<bool> isMigrationRequired() async => false;
  @override
  Future<LegacyMigrationPreview> preview() =>
      throw StateError('No migration required');
  @override
  Future<void> migrate(DateTime at) async {}
}

void main() {
  testWidgets(
    'production outer scope reaches Dashboard and every workspace destination',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final migration = MigrationController(gateway: _NoMigration());
      addTearDown(() async {
        migration.dispose();
        await db.close();
      });
      // main() has an outer scope; the startup gate supplies the database
      // only in the inner workspace scope after migration.
      await tester.pumpWidget(
        ProviderScope(
          child: QuadrantPlannerApp(
            database: db,
            migrationController: migration,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(QuadrantBoard), findsOneWidget);
      final destinations = [
        (LogicalKeyboardKey.digit2, InboxPage),
        (LogicalKeyboardKey.digit3, TasksPage),
        (LogicalKeyboardKey.digit4, ProjectsPage),
        (LogicalKeyboardKey.digit5, PlannerPage),
        (LogicalKeyboardKey.digit6, ReportsPage),
        (LogicalKeyboardKey.digit7, ProfileSettings),
        (LogicalKeyboardKey.digit1, QuadrantBoard),
      ];
      for (final (key, page) in destinations) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(page), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('migration gate opens the real workspace without build errors', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final migration = MigrationController(gateway: _NoMigration());
    addTearDown(() async {
      migration.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      QuadrantPlannerApp(database: db, migrationController: migration),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QuadrantBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
