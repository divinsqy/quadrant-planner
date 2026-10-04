import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class ReportSample {
  final String filename;
  final Uint8List bytes;
  const ReportSample({required this.filename, required this.bytes});
}

abstract interface class ReportFileGateway {
  Future<ReportSample?> pickStyleSample();
  Future<bool> save({required String filename, required Uint8List bytes});
  Future<void> copyPlainText(String value);
}

class DesktopReportFileGateway implements ReportFileGateway {
  @override
  Future<ReportSample?> pickStyleSample() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '周报样式样本',
          extensions: ['xls', 'xlsx', 'md', 'txt'],
          uniformTypeIdentifiers: [
            'com.microsoft.excel.xls',
            'org.openxmlformats.spreadsheetml.sheet',
            'net.daringfireball.markdown',
            'public.plain-text',
          ],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > 10 * 1024 * 1024) throw ArgumentError('样本超过10MB');
    return ReportSample(filename: file.name, bytes: await file.readAsBytes());
  }

  @override
  Future<bool> save({
    required String filename,
    required Uint8List bytes,
  }) async {
    final extension = path.extension(filename).substring(1);
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [
        XTypeGroup(
          label: extension == 'xlsx' ? 'Excel 周报' : 'Markdown 周报',
          extensions: [extension],
          uniformTypeIdentifiers: [
            extension == 'xlsx'
                ? 'org.openxmlformats.spreadsheetml.sheet'
                : 'net.daringfireball.markdown',
          ],
        ),
      ],
    );
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      name: filename,
      mimeType: extension == 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/markdown',
    ).saveTo(location.path);
    return true;
  }

  @override
  Future<void> copyPlainText(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}
