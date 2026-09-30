class TaskDependency {
  final String id;
  final String taskId;
  final String dependsOnTaskId;
  final DateTime createdAt;

  const TaskDependency({
    required this.id,
    required this.taskId,
    required this.dependsOnTaskId,
    required this.createdAt,
  });
}
