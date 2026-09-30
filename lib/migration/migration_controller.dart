import 'dart:io';

import 'package:flutter/foundation.dart';

import 'legacy_migration_service.dart';
import 'legacy_models.dart';

abstract interface class MigrationGateway {
  Future<bool> isMigrationRequired();
  Future<LegacyMigrationPreview> preview();
  Future<void> migrate(DateTime at);
}

enum MigrationPhase {
  checking,
  previewRequired,
  importing,
  ready,
  failed,
}

class MigrationController extends ChangeNotifier {
  final MigrationGateway gateway;
  final DateTime Function() _clock;

  MigrationController({
    required this.gateway,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  MigrationPhase phase = MigrationPhase.checking;
  LegacyMigrationPreview? previewValue;
  Object? error;

  Future<void> initialize() async {
    phase = MigrationPhase.checking;
    error = null;
    notifyListeners();

    try {
      if (!await gateway.isMigrationRequired()) {
        phase = MigrationPhase.ready;
        notifyListeners();
        return;
      }

      previewValue = await gateway.preview();
      phase = MigrationPhase.previewRequired;
      notifyListeners();
    } catch (caught) {
      error = caught;
      phase = MigrationPhase.failed;
      notifyListeners();
    }
  }

  Future<void> importLegacy() async {
    phase = MigrationPhase.importing;
    error = null;
    notifyListeners();

    try {
      await gateway.migrate(_clock().toUtc());
      phase = MigrationPhase.ready;
      notifyListeners();
    } catch (caught) {
      error = caught;
      phase = MigrationPhase.failed;
      notifyListeners();
    }
  }

  Future<void> retry() => initialize();

  void continueWithEmptyV1() {
    error = null;
    phase = MigrationPhase.ready;
    notifyListeners();
  }
}

class LegacyMigrationServiceGateway implements MigrationGateway {
  final LegacyMigrationService service;
  final String legacyDatabasePath;

  const LegacyMigrationServiceGateway({
    required this.service,
    required this.legacyDatabasePath,
  });

  @override
  Future<bool> isMigrationRequired() async {
    if (!await File(legacyDatabasePath).exists()) {
      return false;
    }
    return !(await service.hasSuccessfulMigration());
  }

  @override
  Future<LegacyMigrationPreview> preview() => service.preview();

  @override
  Future<void> migrate(DateTime at) async {
    await service.migrate(migrationAt: at);
  }
}
