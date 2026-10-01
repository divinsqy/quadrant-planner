import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_clusterer.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_models.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_viewport.dart';

void main() {
  group('QuadrantViewport', () {
    const size = Size(600, 400);
    const padding = EdgeInsets.all(20);

    test('maps urgency right and importance upward with round-trip stability', () {
      const viewport = QuadrantViewport();

      expect(
        viewport.dataToScreen(const Offset(0, 0), size, padding),
        const Offset(20, 380),
      );
      expect(
        viewport.dataToScreen(const Offset(100, 100), size, padding),
        const Offset(580, 20),
      );

      const data = Offset(73, 28);
      final screen = viewport.dataToScreen(data, size, padding);
      final restored = viewport.screenToData(screen, size, padding);

      expect(restored.dx, closeTo(data.dx, 0.001));
      expect(restored.dy, closeTo(data.dy, 0.001));
    });

    test('zoom and pan preserve valid data transforms', () {
      const viewport = QuadrantViewport();
      final zoomed = viewport.zoomBy(2).panByData(const Offset(10, -5));

      final center = zoomed.screenToData(
        const Offset(300, 200),
        size,
        padding,
      );

      expect(center.dx, closeTo(60, 0.001));
      expect(center.dy, closeTo(45, 0.001));
      expect(zoomed.zoom, 2);
    });
  });

  group('QuadrantClusterer', () {
    const viewport = QuadrantViewport();
    const size = Size(600, 400);
    const padding = EdgeInsets.all(20);

    test('coincident and nearby tasks cluster without losing members', () {
      final points = [
        point('a', 50, 50),
        point('b', 50, 50),
        point('c', 51, 50),
        point('far', 90, 90),
      ];

      final clusters = const QuadrantClusterer().cluster(
        points: points,
        viewport: viewport,
        size: size,
        padding: padding,
        radiusPx: 12,
      );

      expect(clusters, hasLength(2));
      final dense = clusters.singleWhere((c) => c.members.length == 3);
      expect(dense.members.map((e) => e.id).toSet(), {'a', 'b', 'c'});
      expect(
        dense.screenCenter,
        isNot(const Offset(0, 0)),
      );
    });

    test('hit index resolves a cluster near the pointer', () {
      final clusters = const QuadrantClusterer().cluster(
        points: [point('a', 50, 50), point('b', 50, 50)],
        viewport: viewport,
        size: size,
        padding: padding,
        radiusPx: 12,
      );
      final index = QuadrantHitTestIndex(
        clusters: clusters,
        cellSize: 32,
      );

      final hit = index.hitTest(const Offset(300, 200), radiusPx: 18);

      expect(hit, isNotNull);
      expect(hit!.members.map((e) => e.id).toSet(), {'a', 'b'});
      expect(index.hitTest(const Offset(20, 20), radiusPx: 10), isNull);
    });
  });

  test('thresholds clamp to the 0 to 100 coordinate range', () {
    const raw = QuadrantThresholds(
      urgency: -12,
      importance: 143,
    );

    final clamped = raw.clamped();

    expect(clamped.urgency, 0);
    expect(clamped.importance, 100);
  });
}

QuadrantTaskPoint point(String id, int urgency, int importance) {
  return QuadrantTaskPoint(
    id: id,
    title: id,
    projectId: null,
    urgency: urgency,
    importance: importance,
    workload: QuadrantPointWorkload.medium,
    statusLabel: '已规划',
    metadata: const {},
  );
}
