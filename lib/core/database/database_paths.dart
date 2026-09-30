import 'package:path/path.dart' as p;

class DatabasePaths {
  final String v1DatabasePath;
  final String legacyDatabasePath;

  const DatabasePaths({
    required this.v1DatabasePath,
    required this.legacyDatabasePath,
  });

  factory DatabasePaths.forPlatform({required String basePath}) {
    return DatabasePaths(
      v1DatabasePath: p.join(basePath, 'quadrant_v1.sqlite'),
      legacyDatabasePath: p.join(basePath, 'quadrant.sqlite'),
    );
  }
}
