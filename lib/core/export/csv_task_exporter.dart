import '../database/app_database.dart';
import '../database/user_data_schema.dart';

class CsvTaskExporter {
  final AppDatabase db;
  CsvTaskExporter(this.db);
  Future<String> render({
    bool includeDeleted = true,
  }) => db.transaction(() async {
    final spec = (await UserDataSchema.load(db)).table('tasks');
    final rows = await db.customSelect(
      '''SELECT t.*,p.name AS project_name,
      (SELECT group_concat(name, ' | ') FROM (SELECT g.name FROM task_tags l JOIN tags g ON g.id=l.tag_id WHERE l.task_id=t.id ORDER BY g.name)) AS tag_names
      FROM tasks t LEFT JOIN projects p ON p.id=t.project_id ${includeDeleted ? '' : 'WHERE t.deleted_at IS NULL'} ORDER BY t.created_at,t.id''',
    ).get();
    final columns = [...spec.columns, 'project_name', 'tag_names'];
    return '${[columns.map(_cell).join(','), ...rows.map((row) => columns.map((key) => _cell(row.data[key])).join(','))].join('\r\n')}\r\n';
  });
  String _cell(Object? value) {
    final text = value?.toString() ?? '';
    return RegExp('[,"\r\n]').hasMatch(text)
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }
}
