import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/migration/legacy_models.dart';
import 'package:quadrant_planner/migration/migration_controller.dart';
import 'package:quadrant_planner/migration/migration_screen.dart';

class FakeMigrationGateway implements MigrationGateway {
  FakeMigrationGateway({
    required this.required,
    this.failPreview = false,
    this.failMigration = false,
  });

  bool required;
  bool failPreview;
  bool failMigration;
  int previewCalls = 0;
  int migrateCalls = 0;

  @override
  Future<bool> isMigrationRequired() async => required;

  @override
  Future<LegacyMigrationPreview> preview() async {
    previewCalls += 1;
    if (failPreview) throw StateError('preview failed');
    return const LegacyMigrationPreview(
      taskCount: 37,
      tagCount: 8,
      eventCount: 126,
      skipped: <LegacySkippedEntity>[],
    );
  }

  @override
  Future<void> migrate(DateTime at) async {
    migrateCalls += 1;
    if (failMigration) throw StateError('migration failed');
    required = false;
  }
}

Widget appFor(FakeMigrationGateway gateway) {
  final controller = MigrationController(
    gateway: gateway,
    clock: () => DateTime.utc(2026, 9, 30, 9),
  );
  return MaterialApp(
    home: MigrationScreen(
      controller: controller,
      readyBuilder: (_) => const Text('READY_APP'),
    ),
  );
}

void main() {
  testWidgets('no legacy migration requirement goes straight to the app', (
    tester,
  ) async {
    final gateway = FakeMigrationGateway(required: false);

    await tester.pumpWidget(appFor(gateway));
    await tester.pumpAndSettle();

    expect(find.text('READY_APP'), findsOneWidget);
    expect(gateway.previewCalls, 0);
  });

  testWidgets('migration preview shows source counts and import action', (
    tester,
  ) async {
    final gateway = FakeMigrationGateway(required: true);

    await tester.pumpWidget(appFor(gateway));
    await tester.pumpAndSettle();

    expect(find.textContaining('37'), findsWidgets);
    expect(find.textContaining('8'), findsWidgets);
    expect(find.text('导入到 v1.0'), findsOneWidget);
    expect(find.textContaining('删除旧数据库'), findsNothing);
  });

  testWidgets('successful import enters the ready app', (tester) async {
    final gateway = FakeMigrationGateway(required: true);

    await tester.pumpWidget(appFor(gateway));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入到 v1.0'));
    await tester.pumpAndSettle();

    expect(gateway.migrateCalls, 1);
    expect(find.text('READY_APP'), findsOneWidget);
  });

  testWidgets('migration failure offers retry and continue with empty v1', (
    tester,
  ) async {
    final gateway = FakeMigrationGateway(
      required: true,
      failMigration: true,
    );

    await tester.pumpWidget(appFor(gateway));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入到 v1.0'));
    await tester.pumpAndSettle();

    expect(find.textContaining('migration failed'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('继续使用新的空白 v1'), findsOneWidget);
    expect(find.textContaining('删除旧数据库'), findsNothing);

    await tester.tap(find.text('继续使用新的空白 v1'));
    await tester.pumpAndSettle();

    expect(find.text('READY_APP'), findsOneWidget);
  });
}
