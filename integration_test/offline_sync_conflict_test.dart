import 'package:integration_test/integration_test.dart';

import '../test/support/v1_journeys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  offlineSyncConflictJourney();
}
