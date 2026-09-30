import 'dart:io';

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

  static Future<DatabasePaths> current() async {
    final String basePath;
    if (Platform.isWindows) {
      final root =
          Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
      basePath = p.join(root, 'QuadrantPlanner');
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      basePath = p.join(
        home,
        'Library',
        'Application Support',
        'QuadrantPlanner',
      );
    } else {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      basePath = p.join(home, '.local', 'share', 'QuadrantPlanner');
    }

    await Directory(basePath).create(recursive: true);
    return DatabasePaths.forPlatform(basePath: basePath);
  }
}
