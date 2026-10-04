import 'dart:convert';

class SyncOperation {
  final String operationId, entityKind, entityId;
  final int baseRevision;
  final Set<String> changedFields;
  final Map<String, Object?> payload, base;
  final bool explicitRestore;
  const SyncOperation({
    required this.operationId,
    required this.entityKind,
    required this.entityId,
    required this.baseRevision,
    required this.changedFields,
    required this.payload,
    this.base = const {},
    this.explicitRestore = false,
  });
  factory SyncOperation.fromRow(Map<String, Object?> row) => SyncOperation(
    operationId: row['operation_id'] as String,
    entityKind: row['entity_kind'] as String,
    entityId: row['entity_id'] as String,
    baseRevision: row['base_revision'] as int,
    changedFields: (jsonDecode(row['changed_fields_json'] as String) as List)
        .cast<String>()
        .toSet(),
    payload: Map<String, Object?>.from(
      jsonDecode(row['payload_json'] as String) as Map,
    ),
    base: Map<String, Object?>.from(
      jsonDecode(row['base_json'] as String? ?? '{}') as Map,
    ),
    explicitRestore: row['explicit_restore'] == 1,
  );
  Map<String, Object?> toJson() => {
    'operation_id': operationId,
    'entity_kind': entityKind,
    'entity_id': entityId,
    'base_revision': baseRevision,
    'changed_fields': changedFields.toList(),
    'payload': payload,
    'explicit_restore': explicitRestore,
  };
}
