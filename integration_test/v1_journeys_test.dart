import 'package:integration_test/integration_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quadrant_planner/app/workspace_providers.dart';
import 'package:quadrant_planner/core/sync/secure_session_store.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/main.dart' as production;

import '../test/support/v1_journeys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('production entry point opens the real Dashboard', (
    tester,
  ) async {
    production.main();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(QuadrantBoard), findsOneWidget);
    final workspace = ProviderScope.containerOf(
      tester.element(find.byType(QuadrantBoard)),
    );
    // A frame can settle before the background SQLite isolate finishes opening.
    // Verify actual data readiness before closing the application under test.
    await tester.runAsync(() async {
      final version = await workspace
          .read(workspaceDatabaseProvider)
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 5);
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  taskToReportJourney();
  offlineSyncConflictJourney();
  backupRestoreJourney();
  legacyMigrationJourney();
  testWidgets(
    'native OS secure storage round trip uses an isolated probe key',
    (tester) async {
      final storage = const OsSecureSessionStore().storage;
      final key =
          'quadrant.release.probe.${DateTime.now().microsecondsSinceEpoch}';
      await tester.runAsync(() async {
        try {
          await storage.write(key: key, value: 'release-boundary-fixture');
          expect(await storage.read(key: key), 'release-boundary-fixture');
        } finally {
          await storage.delete(key: key);
        }
        expect(await storage.read(key: key), isNull);
      });
    },
  );
}
