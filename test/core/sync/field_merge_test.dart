import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/core/sync/field_merge.dart';

void main() {
  test('independent fields merge, overlapping fields remain conflicts', () {
    final base = <String, Object?>{
      'title': 'RTL',
      'deadline': 1,
      'importance': 50,
    };
    final result = mergeEntity(
      base,
      {...base, 'title': 'UVM'},
      {...base, 'deadline': 2},
    );
    expect(result.payload, {'title': 'UVM', 'deadline': 2, 'importance': 50});
    expect(result.conflicts, isEmpty);
    final conflict = mergeEntity(
      base,
      {...base, 'importance': 60},
      {...base, 'importance': 70},
    );
    expect(conflict.conflicts.single.field, 'importance');
  });
  test('remote delete defeats stale offline edits; local delete defeats live remote', () {
    final base = <String, Object?>{'title': 'AXI', 'deleted_at': null};
    final result = mergeEntity(
      base,
      {...base, 'title': 'offline'},
      {...base, 'deleted_at': 100},
    );
    expect(result.payload['deleted_at'], 100);
    expect(result.conflicts.single.field, '_deletion');
    final reversed = mergeEntity(
      base,
      {...base, 'deleted_at': 100},
      {...base, 'title': 'remote'},
    );
    expect(reversed.payload['deleted_at'], 100);
  });
}
