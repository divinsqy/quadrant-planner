import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/features/search/application/global_search_controller.dart';
import 'package:quadrant_planner/features/search/presentation/command_palette.dart';

class FakeSearchSource implements GlobalSearchSource {
  @override
  Future<List<GlobalSearchResult>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    return const [
      GlobalSearchResult(
        id: 'task-1',
        type: SearchEntityType.task,
        title: 'AXI 4KB boundary',
        subtitle: 'DMAC',
      ),
      GlobalSearchResult(
        id: 'project-1',
        type: SearchEntityType.project,
        title: 'DMAC',
        subtitle: 'Project',
      ),
    ];
  }
}

void main() {
  test('controller returns task and project matches from its source', () async {
    final controller = GlobalSearchController(source: FakeSearchSource());

    await controller.search('DMA');

    expect(controller.results, hasLength(2));
    expect(controller.results.first.type, SearchEntityType.task);
    expect(controller.results.last.type, SearchEntityType.project);
  });

  testWidgets('command palette opens a selected search result', (tester) async {
    final controller = GlobalSearchController(source: FakeSearchSource());
    GlobalSearchResult? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPalette(
            controller: controller,
            onOpenResult: (result) => opened = result,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'DMA');
    await tester.pump();
    await tester.pump();

    expect(find.text('AXI 4KB boundary'), findsOneWidget);
    expect(find.text('DMAC'), findsWidgets);

    await tester.tap(find.text('AXI 4KB boundary'));
    await tester.pump();

    expect(opened?.id, 'task-1');
    expect(opened?.type, SearchEntityType.task);
  });
}
