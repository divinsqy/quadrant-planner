import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_board.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_painter.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_clusterer.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_models.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_viewport.dart';

import '../support/task_fixtures.dart';

void main() {
  test('1000 tasks retain membership with bounded clustering and 20000 indexed hits', () {
    final points = List.generate(
      1000,
      (i) => QuadrantTaskPoint.fromSnapshot(fixtureSnapshot(i)),
    );
    final timer = Stopwatch()..start();
    final clusters = const QuadrantClusterer().cluster(
      points: points,
      viewport: const QuadrantViewport(),
      size: const Size(2000, 1200),
      padding: EdgeInsets.zero,
      radiusPx: 14,
    );
    timer.stop();
    final clusterTime = timer.elapsedMicroseconds;
    expect(
      clusters.expand((c) => c.members).map((p) => p.id).toSet().length,
      1000,
    );
    expect(timer.elapsedMilliseconds, lessThan(3000));
    final isolated = List.generate(
      1000,
      (i) => QuadrantCluster(
        members: [points[i]],
        screenCenter: Offset((i % 40) * 50.0, (i ~/ 40) * 50.0),
      ),
    );
    final index = QuadrantHitTestIndex(clusters: isolated, cellSize: 40);
    timer.reset();
    timer.start();
    for (var i = 0; i < 20000; i++) {
      final c = isolated[i % 1000];
      expect(index.hitTest(c.screenCenter, radiusPx: 20), same(c));
    }
    timer.stop();
    expect(timer.elapsedMilliseconds, lessThan(3000));
    debugPrint(
      'BENCHMARK cluster1000=${clusterTime}us hit20000=${timer.elapsedMicroseconds}us',
    );
  });
  testWidgets(
    '1000-task hover reuses geometry and data changes invalidate it',
    (tester) async {
      final tasks = List.generate(1000, fixtureSnapshot);
      Widget app() => MaterialApp(
        home: Scaffold(
          body: QuadrantBoard(
            tasks: tasks,
            thresholds: const QuadrantThresholds(urgency: 50, importance: 50),
          ),
        ),
      );
      await tester.pumpWidget(app());
      QuadrantPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is QuadrantPainter,
                    ),
                  )
                  .painter!
              as QuadrantPainter;
      final original = painter().clusters;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final cluster in original.take(20)) {
        await mouse.moveTo(cluster.screenCenter);
        await tester.pump();
        expect(painter().clusters, same(original));
      }
      final updated = [fixtureSnapshot(1001)];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuadrantBoard(
              tasks: updated,
              thresholds: const QuadrantThresholds(urgency: 50, importance: 50),
            ),
          ),
        ),
      );
      expect(painter().clusters.expand((c) => c.members).single.id, 't-1001');
    },
  );
}
