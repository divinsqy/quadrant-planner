class Project {
  final String id;
  final String name;
  final String objective;
  final DateTime? deadline;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Project({
    required this.id,
    required this.name,
    required this.objective,
    required this.deadline,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
}
