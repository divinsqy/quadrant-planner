import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../core/database/app_database.dart';
import 'legacy_migration_service.dart';
import 'legacy_models.dart' show LegacyMigrationPreview;

export 'legacy_models.dart' show LegacyMigrationPreview;

abstract interface class MigrationGateway {
  Future<bool> isMigrationRequired();
  Future<LegacyMigrationPreview> preview();
  Future<void> migrate(DateTime at);
}

class LegacyMigrationGateway implements MigrationGateway {
  final AppDatabase database;
  final String legacyDatabasePath;
  final LegacyMigrationService service;

  const LegacyMigrationGateway({
    required this.database,
    required this.legacyDatabasePath,
    required this.service,
  });

  @override
  Future<bool> isMigrationRequired() async {
    final file = File(legacyDatabasePath);
    if (!await file.exists()) {
      return false;
    }

    final sourceHash = sha256.convert(await file.readAsBytes()).toString();
    final prior = await (database.select(database.migrationState)
          ..where(
            (row) =>
                row.sourceHash.equals(sourceHash) & row.success.equals(true),
          ))
        .getSingleOrNull();
    return prior == null;
  }

  @override
  Future<LegacyMigrationPreview> preview() => service.preview();

  @override
  Future<void> migrate(DateTime at) async {
    await service.migrate(migrationAt: at);
  }
}

enum MigrationStage {
  checking,
  previewRequired,
  importing,
  failed,
  ready,
}

class MigrationController extends ChangeNotifier {
  final MigrationGateway gateway;
  final DateTime Function() _clock;

  MigrationStage stage = MigrationStage.checking;
  LegacyMigrationPreview? preview;
  Object? error;

  bool _initializing = false;

  MigrationController({
    required this.gateway,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    stage = MigrationStage.checking;
    error = null;
    notifyListeners();

    try {
      if (!await gateway.isMigrationRequired()) {
        stage = MigrationStage.ready;
        return;
      }
      preview = await gateway.preview();
      stage = MigrationStage.previewRequired;
    } catch (caught) {
      error = caught;
      stage = MigrationStage.failed;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> importLegacy() async {
    if (stage != MigrationStage.previewRequired &&
        stage != MigrationStage.failed) {
      return;
    }

    stage = MigrationStage.importing;
    error = null;
    notifyListeners();

    try {
      await gateway.migrate(_clock().toUtc());
      stage = MigrationStage.ready;
    } catch (caught) {
      error = caught;
      stage = MigrationStage.failed;
    }
    notifyListeners();
  }

  Future<void> retry() => initialize();

  void continueWithEmptyV1() {
    error = null;
    stage = MigrationStage.ready;
    notifyListeners();
  }
}
