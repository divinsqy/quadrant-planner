import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/tags/tag.dart' as domain;

class TagRepository {
  final AppDatabase _db;

  TagRepository(this._db);

  Stream<Map<String, List<String>>> watchTaskTags() {
    final query = _db.select(_db.taskTags).join([
      innerJoin(_db.tags, _db.tags.id.equalsExp(_db.taskTags.tagId)),
    ])..where(_db.tags.archivedAt.isNull());
    query.orderBy([OrderingTerm.asc(_db.tags.name)]);
    return query.watch().map((rows) {
      final result = <String, List<String>>{};
      for (final row in rows) {
        final link = row.readTable(_db.taskTags);
        (result[link.taskId] ??= []).add(row.readTable(_db.tags).name);
      }
      return Map.unmodifiable({
        for (final entry in result.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      });
    });
  }

  Future<List<domain.Tag>> search(String query, {int limit = 20}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final pattern = '%$normalized%';
    final statement = _db.select(_db.tags)
      ..where((row) => row.archivedAt.isNull() & row.name.like(pattern))
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(limit);

    final rows = await statement.get();
    return rows
        .map(
          (row) => domain.Tag(
            id: row.id,
            name: row.name,
            archivedAt: row.archivedAt,
          ),
        )
        .toList(growable: false);
  }
}
