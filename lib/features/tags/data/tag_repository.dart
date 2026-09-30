import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../domain/tags/tag.dart' as domain;

class TagRepository {
  final AppDatabase _db;

  TagRepository(this._db);

  Future<List<domain.Tag>> search(
    String query, {
    int limit = 20,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final pattern = '%$normalized%';
    final statement = _db.select(_db.tags)
      ..where(
        (row) =>
            row.archivedAt.isNull() &
            row.name.like(pattern),
      )
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
