import 'dart:convert';

import '../database/app_database.dart';
import '../database/user_data_schema.dart';
import '../sync/credential_boundary.dart';

class JsonDataExporter {
  final AppDatabase db;
  JsonDataExporter(this.db);
  Future<Map<String, Object?>> data() => db.transaction(() async {
    final schema = await UserDataSchema.load(db);
    final tables = <String, Object?>{};
    for (final spec in schema.tables) {
      tables[spec.name] =
          (await db
                  .customSelect(
                    'SELECT ${spec.columns.join(',')} FROM ${spec.name} ORDER BY rowid',
                  )
                  .get())
              .map((row) => row.data)
              .toList();
    }
    final data = {
      'format': 'quadrant-user-data',
      'schema_version': db.schemaVersion,
      'timestamp_encoding': 'unix-seconds-utc',
      'tables': tables,
    };
    rejectCredentialFields(data);
    return data;
  });
  Future<String> render() async =>
      const JsonEncoder.withIndent('  ').convert(await data());
}
