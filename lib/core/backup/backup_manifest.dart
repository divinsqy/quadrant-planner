class BackupManifest {
  final int schemaVersion;
  final String sha256, createdAt;
  final Map<String, int> counts;
  const BackupManifest({
    required this.schemaVersion,
    required this.sha256,
    required this.createdAt,
    required this.counts,
  });
  Map<String, Object?> toJson() => {
    'format': 'quadrant-backup',
    'format_version': 1,
    'schema_version': schemaVersion,
    'created_at': createdAt,
    'data_sha256': sha256,
    'counts': counts,
  };
  factory BackupManifest.fromJson(Map value) {
    if (value['format'] != 'quadrant-backup' || value['format_version'] != 1) {
      throw const FormatException('Incompatible backup');
    }
    return BackupManifest(
      schemaVersion: value['schema_version'] as int,
      sha256: value['data_sha256'] as String,
      createdAt: value['created_at'] as String,
      counts: Map<String, int>.from(value['counts'] as Map),
    );
  }
}
