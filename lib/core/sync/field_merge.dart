import 'dart:convert';

bool sameValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && sameValue(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (index) => index,
        ).every((i) => sameValue(a[i], b[i]));
  }
  return a == b;
}

bool isDeleted(Map<String, Object?> value) =>
    value['deleted_at'] != null ||
    value['_deleted'] == 1 ||
    value['_deleted'] == true;

class FieldConflict {
  final String field;
  final Object? base, local, remote;
  const FieldConflict(this.field, this.base, this.local, this.remote);
}

class MergeResult {
  final Map<String, Object?> payload;
  final List<FieldConflict> conflicts;
  const MergeResult(this.payload, this.conflicts);
}

MergeResult mergeEntity(
  Map<String, Object?> base,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) {
  final conflicts = <FieldConflict>[];
  if (isDeleted(local) != isDeleted(remote)) {
    final deleted = isDeleted(local) ? local : remote;
    final live = isDeleted(local) ? remote : local;
    if (!sameValue(base, live)) {
      conflicts.add(FieldConflict('_deletion', base, local, remote));
    }
    return MergeResult(Map.of(deleted), conflicts);
  }
  final merged = <String, Object?>{};
  for (final key in {...base.keys, ...local.keys, ...remote.keys}) {
    final l = local[key], r = remote[key], b = base[key];
    if (key == 'updated_at' && l is num && r is num) {
      merged[key] = l > r ? l : r;
      continue;
    }
    if (sameValue(l, b)) {
      merged[key] = r;
    } else if (sameValue(r, b) || sameValue(l, r)) {
      merged[key] = l;
    } else {
      merged[key] = l;
      conflicts.add(FieldConflict(key, b, l, r));
    }
  }
  return MergeResult(merged, conflicts);
}

String encodedValue(Object? value) => jsonEncode(value);
