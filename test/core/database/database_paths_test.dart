import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/database/database_paths.dart';

void main() {
  test('v1 and legacy databases are distinct sibling files', () {
    final paths = DatabasePaths.forPlatform(basePath: '/tmp/QuadrantPlanner');

    expect(paths.v1DatabasePath, '/tmp/QuadrantPlanner/quadrant_v1.sqlite');
    expect(paths.legacyDatabasePath, '/tmp/QuadrantPlanner/quadrant.sqlite');
    expect(paths.v1DatabasePath, isNot(paths.legacyDatabasePath));
  });
}
