import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

class SpreadsheetStyleParser {
  String text(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    final lines = <String>[];
    for (final sheet in workbook.tables.values) {
      for (final row in sheet.rows) {
        final cells = row
            .map((cell) => cell?.value?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList();
        // Metadata and Q/A can share a row. Keep individual field boundaries.
        lines.addAll(cells);
        if (cells.length > 1 && RegExp(r'^\d+$').hasMatch(cells.first.trim())) {
          lines.add('${cells.first}. ${cells.skip(1).join(' ')}');
        }
      }
    }
    return lines.join('\n');
  }
}
