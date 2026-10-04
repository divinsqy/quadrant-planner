import 'dart:typed_data';

import '../../../domain/reports/report_style_profile.dart';
import '../data/report_repository.dart';
import '../import/report_style_importer.dart';

class ReportStyleService {
  final ReportRepository reports;
  final ReportStyleImporter importer;
  ReportStyleService(this.reports, {ReportStyleImporter? importer})
    : importer = importer ?? ReportStyleImporter();
  Future<ReportStyleProfile> importSample({
    required String filename,
    required Uint8List bytes,
  }) async {
    final style = await importer.importBytes(filename: filename, bytes: bytes);
    await reports.saveStyle(style);
    return style;
  }
}
