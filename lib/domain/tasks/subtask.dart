class Subtask {
  final String id;
  final String taskId;
  final String title;
  final bool completed;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    required this.completed,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });
}
