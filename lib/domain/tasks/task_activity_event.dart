class TaskActivityEvent {
  final String id;
  final String taskId;
  final String type;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;

  const TaskActivityEvent({
    required this.id,
    required this.taskId,
    required this.type,
    required this.occurredAt,
    required this.payload,
  });
}
