import '../../projects/data/project_repository.dart';
import '../../tasks/data/task_repository.dart';
import '../application/global_search_controller.dart';

class RepositoryGlobalSearchSource implements GlobalSearchSource {
  final TaskRepository tasks;
  final ProjectRepository projects;

  const RepositoryGlobalSearchSource({
    required this.tasks,
    required this.projects,
  });

  @override
  Future<List<GlobalSearchResult>> search(String query) async {
    final taskMatches = await tasks.search(query, limit: 12);
    final projectMatches = await projects.search(query, limit: 8);

    return [
      for (final task in taskMatches)
        GlobalSearchResult(
          id: task.id,
          type: SearchEntityType.task,
          title: task.title,
          subtitle: task.status.name,
        ),
      for (final project in projectMatches)
        GlobalSearchResult(
          id: project.id,
          type: SearchEntityType.project,
          title: project.name,
          subtitle: project.objective,
        ),
    ];
  }
}
