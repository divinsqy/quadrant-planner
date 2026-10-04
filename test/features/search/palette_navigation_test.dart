import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/features/search/application/global_search_controller.dart';
import 'package:quadrant_planner/features/search/presentation/command_palette.dart';

class _EmptySource implements GlobalSearchSource {
  @override
  Future<List<GlobalSearchResult>> search(String query) async => [];
}

void main() {
  testWidgets('command palette exposes workspace navigation', (tester) async {
    final controller = GlobalSearchController(source: _EmptySource());
    addTearDown(controller.dispose);
    String? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPalette(
            controller: controller,
            onOpenResult: (_) {},
            onNavigate: (name) => destination = name,
          ),
        ),
      ),
    );
    await tester.tap(find.text('前往项目'));
    expect(destination, 'projects');
  });
}
