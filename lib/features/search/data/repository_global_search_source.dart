import '../../projects/data/project_repository.dart';
import '../../tags/data/tag_repository.dart';
import '../../tasks/data/task_repository.dart';
import '../application/global_search_controller.dart';

class RepositoryGlobalSearchSource implements GlobalSearchSource {
  final TaskRepository tasks;
  final ProjectRepository projects;
  final TagRepository tags;

  const RepositoryGlobalSearchSource({
    required this.tasks,
    required this.projects,
    required this.tags,
  });

  @override
  Future<List<GlobalSearchResult>> search(String query) async {
    final taskMatches = await tasks.search(query, limit: 12);
    final projectMatches = await projects.search(query, limit: 8);
    final tagMatches = await tags.search(query, limit: 8);

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
      for (final tag in tagMatches)
        GlobalSearchResult(
          id: tag.id,
          type: SearchEntityType.tag,
          title: tag.name,
          subtitle: '标签',
        ),
    ];
  }
}
