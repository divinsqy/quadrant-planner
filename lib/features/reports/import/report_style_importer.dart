import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../domain/reports/report_style_profile.dart';
import 'markdown_style_parser.dart';
import 'spreadsheet_style_parser.dart';

class ReportStyleParseError implements Exception {
  final String message;
  const ReportStyleParseError(this.message);
  @override
  String toString() => '样式导入失败：$message';
}

class ReportStyleImporter {
  Future<ReportStyleProfile> importBytes({
    required String filename,
    required Uint8List bytes,
  }) async {
    final extension = path.extension(filename).toLowerCase();
    if (!['.xls', '.xlsx', '.md', '.txt'].contains(extension)) {
      throw const ReportStyleParseError('支持 .xls/.xlsx/.md/.txt');
    }
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const ReportStyleParseError('样本为空或超过10MB');
    }
    final id = const Uuid().v4();
    final name = path.basenameWithoutExtension(filename);
    try {
      return await Isolate.run(() {
        bool starts(List<int> magic) =>
            bytes.length >= magic.length &&
            List.generate(
              magic.length,
              (i) => bytes[i] == magic[i],
            ).every((v) => v);
        final spreadsheet =
            starts([0x50, 0x4b, 3, 4]) ||
            starts([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
        String text;
        if (spreadsheet) {
          text = SpreadsheetStyleParser().text(bytes);
        } else if (extension == '.xls' || extension == '.xlsx') {
          throw const FormatException('文件不是可识别的 Excel 工作簿');
        } else if (starts([0xff, 0xfe]) || starts([0xfe, 0xff])) {
          if (bytes.length.isOdd) throw const FormatException('UTF16 文件已截断');
          final little = bytes[0] == 0xff;
          final data = ByteData.sublistView(bytes);
          text = String.fromCharCodes([
            for (var i = 2; i < bytes.length; i += 2)
              data.getUint16(i, little ? Endian.little : Endian.big),
          ]);
        } else {
          text = utf8.decode(bytes).replaceFirst('\ufeff', '');
        }
        return MarkdownStyleParser().parse(text, id: id, name: name);
      });
    } catch (error) {
      throw ReportStyleParseError(
        error is FormatException ? error.message : '文件无法解析，请检查样本格式',
      );
    }
  }
}
