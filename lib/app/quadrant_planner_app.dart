import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/database/database_paths.dart';
import '../migration/legacy_migration_service.dart';
import '../migration/migration_controller.dart';
import '../migration/migration_screen.dart';

class QuadrantPlannerApp extends StatelessWidget {
  const QuadrantPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quadrant Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const _StartupGate(),
    );
  }
}

class _StartupRuntime {
  final AppDatabase database;
  final MigrationController migrationController;

  const _StartupRuntime({
    required this.database,
    required this.migrationController,
  });
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<_StartupRuntime> _runtime = _openRuntime();
  AppDatabase? _database;

  Future<_StartupRuntime> _openRuntime() async {
    final paths = await DatabasePaths.current();
    final database = AppDatabase.open(paths.v1DatabasePath);
    _database = database;

    final service = LegacyMigrationService(
      database: database,
      legacyDatabasePath: paths.legacyDatabasePath,
    );
    final controller = MigrationController(
      gateway: LegacyMigrationGateway(
        database: database,
        legacyDatabasePath: paths.legacyDatabasePath,
        service: service,
      ),
    );
    return _StartupRuntime(
      database: database,
      migrationController: controller,
    );
  }

  @override
  void dispose() {
    _database?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupRuntime>(
      future: _runtime,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              '启动失败：\${snapshot.error}',
            ),
          );
        }
        final runtime = snapshot.data;
        if (runtime == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return MigrationScreen(
          controller: runtime.migrationController,
          readyBuilder: (_) => const Scaffold(
            body: Center(child: Text('Quadrant Planner v1')),
          ),
        );
      },
    );
  }
}
