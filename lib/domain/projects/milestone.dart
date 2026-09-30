class Milestone {
  final String id;
  final String projectId;
  final String name;
  final DateTime? deadline;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Milestone({
    required this.id,
    required this.projectId,
    required this.name,
    required this.deadline,
    required this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });
}
