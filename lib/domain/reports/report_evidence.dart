class ReportEvidenceRef {
  final String id;
  final String kind;
  final String sourceId;
  final String title;
  final String detail;
  final DateTime? occurredAt;
  const ReportEvidenceRef({
    required this.id,
    required this.kind,
    required this.sourceId,
    required this.title,
    required this.detail,
    this.occurredAt,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'sourceId': sourceId,
    'title': title,
    'detail': detail,
    'occurredAt': occurredAt?.toUtc().toIso8601String(),
  };
  factory ReportEvidenceRef.fromJson(Map<String, dynamic> json) =>
      ReportEvidenceRef(
        id: json['id'] as String,
        kind: json['kind'] as String,
        sourceId: json['sourceId'] as String,
        title: json['title'] as String,
        detail: json['detail'] as String,
        occurredAt: json['occurredAt'] == null
            ? null
            : DateTime.parse(json['occurredAt'] as String),
      );
}
