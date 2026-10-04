import '../tasks/task.dart';
import '../tasks/task_status.dart';
import '../tasks/workload.dart';

/// Completed duration divided by total duration, with 30/60/120 minute workload
/// estimates when no explicit estimate exists. Cancelled/deleted work is omitted.
double calculateProjectProgress(Iterable<Task> tasks) {
  var totalMinutes = 0;
  var completedMinutes = 0.0;
  for (final task in tasks) {
    if (task.deletedAt != null || task.status == TaskStatus.cancelled) {
      continue;
    }
    final weight =
        task.estimatedMinutes ??
        switch (task.workload) {
          Workload.small => 30,
          Workload.medium => 60,
          Workload.large => 120,
        };
    totalMinutes += weight;
    if (task.status == TaskStatus.completed) {
      completedMinutes += weight;
    }
  }
  return totalMinutes == 0
      ? 0
      : (completedMinutes / totalMinutes * 100).clamp(0, 100);
}
