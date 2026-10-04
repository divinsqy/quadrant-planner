import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/app/quadrant_planner_app.dart';
import 'package:quadrant_planner/core/database/app_database.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
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
