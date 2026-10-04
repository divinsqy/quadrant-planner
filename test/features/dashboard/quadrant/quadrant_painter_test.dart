import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/domain/planning/planner_candidate.dart';
import 'package:quadrant_planner/domain/quadrant/quadrant.dart';
import 'package:quadrant_planner/domain/tasks/task.dart';
import 'package:quadrant_planner/domain/tasks/task_status.dart';
import 'package:quadrant_planner/domain/tasks/workload.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_models.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_painter.dart';
import 'package:quadrant_planner/features/dashboard/quadrant/quadrant_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff5467a8));

  test(
    'rendered points use stable project colors and neutral unassigned color',
    () async {
      final first = await render(scheme, [
        point('a-1', projectId: 'a'),
        point('b-1', projectId: 'b'),
        point('unassigned'),
      ]);
      final recreated = await render(scheme, [
        point('b-2', projectId: 'b'),
        point('a-2', projectId: 'a'),
        point('unassigned-2'),
      ]);

      // These fixed palette entries are keyed by the persisted project ID,
      // independent of task ID, order, or process-randomized String.hashCode.
      expect(pixel(first, 80, 70), const Color(0xff8054a8));
      expect(pixel(first, 200, 70), const Color(0xff208274));
      expect(pixel(first, 320, 70), scheme.outline);
      expect(pixel(recreated, 80, 70), pixel(first, 200, 70));
      expect(pixel(recreated, 200, 70), pixel(first, 80, 70));
    },
  );

  test('selection keeps project fill and adds a visible halo', () async {
    final planned = point('selected', projectId: 'a');
    final normal = await render(scheme, [planned]);
    final selected = await render(scheme, [
      planned,
    ], selectedTaskId: 'selected');

    expect(pixel(selected, 80, 70), pixel(normal, 80, 70));
    expect(pixel(selected, 91, 70), isNot(pixel(normal, 91, 70)));
  });

  test('recorded in-progress status paints a non-color inner ring', () async {
    final planned = point('planned', projectId: 'a');
    final active = point(
      'active',
      projectId: 'a',
      status: TaskStatus.inProgress,
    );
    final image = await render(scheme, [planned, active]);

    expect(pixel(image, 80, 70), pixel(image, 200, 70));
    expect(pixel(image, 85, 70), isNot(pixel(image, 205, 70)));
  });

  test('workload keeps the existing 6, 8, and 10 pixel radii', () async {
    final background = await render(scheme, const []);
    final image = await render(scheme, [
      point('small', workload: Workload.small),
      point('medium', workload: Workload.medium),
      point('large', workload: Workload.large),
    ]);

    expect(pixel(image, 85, 70), isNot(pixel(background, 85, 70)));
    expect(pixel(image, 87, 70), pixel(background, 87, 70));
    expect(pixel(image, 207, 70), isNot(pixel(background, 207, 70)));
    expect(pixel(image, 209, 70), pixel(background, 209, 70));
    expect(pixel(image, 329, 70), isNot(pixel(background, 329, 70)));
    expect(pixel(image, 331, 70), pixel(background, 331, 70));
  });
}

QuadrantTaskPoint point(
  String id, {
  String? projectId,
  TaskStatus status = TaskStatus.planned,
  Workload workload = Workload.medium,
}) {
  final task = Task.create(
    id: id,
    title: id,
    description: '',
    status: status,
    projectId: projectId,
    importance: 75,
    baseUrgency: 25,
    baseUrgencyAnchorAt: DateTime(2026, 9, 30),
    deadline: null,
    estimatedMinutes: null,
    workload: workload,
    progress: 0,
    includeInWeeklyReport: true,
    createdAt: DateTime(2026, 9, 30),
    updatedAt: DateTime(2026, 9, 30),
  );
  return QuadrantTaskPoint.fromSnapshot(
    TaskPlanningSnapshot(
      task: task,
      currentUrgency: 25,
      quadrant: Quadrant.plan,
      dependenciesSatisfied: true,
      milestoneWorkdaysRemaining: null,
      fitsCurrentSlot: true,
    ),
  );
}

Future<ByteData> render(
  ColorScheme scheme,
  List<QuadrantTaskPoint> points, {
  String? selectedTaskId,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  QuadrantPainter(
    clusters: [
      for (var index = 0; index < points.length; index++)
        QuadrantCluster(
          members: [points[index]],
          screenCenter: Offset(80 + 120.0 * index, 70),
        ),
    ],
    viewport: const QuadrantViewport(),
    thresholds: const QuadrantThresholds(urgency: 50, importance: 50),
    padding: EdgeInsets.zero,
    selectedTaskId: selectedTaskId,
    trajectory: const [],
    colorScheme: scheme,
  ).paint(canvas, const Size(400, 300));
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 300);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return bytes;
}

Color pixel(ByteData bytes, int x, int y) {
  final offset = (y * 400 + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}
