class Tag {
  final String id;
  final String name;
  final DateTime? archivedAt;

  const Tag({
    required this.id,
    required this.name,
    this.archivedAt,
  });
}
