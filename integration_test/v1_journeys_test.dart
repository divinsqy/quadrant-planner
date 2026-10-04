import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/sync/secure_session_store.dart';

import '../test/support/v1_journeys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
