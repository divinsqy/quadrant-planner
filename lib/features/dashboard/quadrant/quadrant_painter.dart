import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'quadrant_models.dart';
import 'quadrant_viewport.dart';
import 'task_trajectory_builder.dart';

class QuadrantPainter extends CustomPainter {
  final List<QuadrantCluster> clusters;
  final QuadrantViewport viewport;
  final QuadrantThresholds thresholds;
  final EdgeInsets padding;
  final String? selectedTaskId;
  final List<TaskTrajectoryPoint> trajectory;
  final ColorScheme colorScheme;

  QuadrantPainter({
    required this.clusters,
    required this.viewport,
    required this.thresholds,
    required this.padding,
    required this.selectedTaskId,
    required this.trajectory,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = viewport.plotRect(size, padding);
    final thresholdPoint = viewport.dataToScreen(
      Offset(
        thresholds.urgency.toDouble(),
        thresholds.importance.toDouble(),
      ),
      size,
      padding,
    );

    _paintQuadrantBackgrounds(canvas, rect, thresholdPoint);
    _paintGrid(canvas, rect, size);
    _paintLabels(canvas, rect, thresholdPoint);
    _paintTrajectory(canvas, size);
    _paintClusters(canvas);
  }

  void _paintQuadrantBackgrounds(
    Canvas canvas,
    Rect rect,
    Offset thresholdPoint,
  ) {
    final x = thresholdPoint.dx.clamp(rect.left, rect.right);
    final y = thresholdPoint.dy.clamp(rect.top, rect.bottom);

    final planPaint = Paint()
      ..color = colorScheme.primaryContainer.withValues(alpha: 0.22);
    final doPaint = Paint()
      ..color = colorScheme.errorContainer.withValues(alpha: 0.20);
    final lowPaint = Paint()
      ..color = colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final expeditePaint = Paint()
      ..color = colorScheme.tertiaryContainer.withValues(alpha: 0.23);

    canvas.drawRect(Rect.fromLTRB(rect.left, rect.top, x, y), planPaint);
    canvas.drawRect(Rect.fromLTRB(x, rect.top, rect.right, y), doPaint);
    canvas.drawRect(Rect.fromLTRB(rect.left, y, x, rect.bottom), lowPaint);
    canvas.drawRect(
      Rect.fromLTRB(x, y, rect.right, rect.bottom),
      expeditePaint,
    );
  }

  void _paintGrid(Canvas canvas, Rect rect, Size size) {
    final minor = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    for (final score in const [25.0, 50.0, 75.0]) {
      final vertical =
          viewport.dataToScreen(Offset(score, 50), size, padding).dx;
      final horizontal =
          viewport.dataToScreen(Offset(50, score), size, padding).dy;
      if (vertical >= rect.left && vertical <= rect.right) {
        canvas.drawLine(
          Offset(vertical, rect.top),
          Offset(vertical, rect.bottom),
          minor,
        );
      }
      if (horizontal >= rect.top && horizontal <= rect.bottom) {
        canvas.drawLine(
          Offset(rect.left, horizontal),
          Offset(rect.right, horizontal),
          minor,
        );
      }
    }

    final thresholdPaint = Paint()
      ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.72)
      ..strokeWidth = 1.6;

    final urgencyX = viewport
        .dataToScreen(
          Offset(thresholds.urgency.toDouble(), 50),
          size,
          padding,
        )
        .dx;
    final importanceY = viewport
        .dataToScreen(
          Offset(50, thresholds.importance.toDouble()),
          size,
          padding,
        )
        .dy;

    if (urgencyX >= rect.left && urgencyX <= rect.right) {
      canvas.drawLine(
        Offset(urgencyX, rect.top),
        Offset(urgencyX, rect.bottom),
        thresholdPaint,
      );
    }
    if (importanceY >= rect.top && importanceY <= rect.bottom) {
      canvas.drawLine(
        Offset(rect.left, importanceY),
        Offset(rect.right, importanceY),
        thresholdPaint,
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = colorScheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintLabels(
    Canvas canvas,
    Rect rect,
    Offset thresholdPoint,
  ) {
    final labels = <_Label>[
      _Label(
        '重点规划',
        Offset(rect.left + 12, rect.top + 10),
      ),
      _Label(
        '立即处理',
        Offset(thresholdPoint.dx + 12, rect.top + 10),
      ),
      _Label(
        '低优先级',
        Offset(rect.left + 12, thresholdPoint.dy + 10),
      ),
      _Label(
        '尽快处理',
        Offset(thresholdPoint.dx + 12, thresholdPoint.dy + 10),
      ),
    ];

    for (final label in labels) {
      if (!rect.contains(label.offset)) {
        continue;
      }
      final text = TextPainter(
        text: TextSpan(
          text: label.text,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 100);
      text.paint(canvas, label.offset);
    }
  }

  void _paintTrajectory(Canvas canvas, Size size) {
    if (trajectory.length < 2) {
      return;
    }

    final path = Path();
    for (var index = 0; index < trajectory.length; index += 1) {
      final point = trajectory[index];
      final screen = viewport.dataToScreen(
        Offset(point.urgency.toDouble(), point.importance.toDouble()),
        size,
        padding,
      );
      if (index == 0) {
        path.moveTo(screen.dx, screen.dy);
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = colorScheme.primary.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintClusters(Canvas canvas) {
    for (final cluster in clusters) {
      final selected = cluster.members.any((point) => point.id == selectedTaskId);
      final workloadRadius = cluster.members
          .map(_pointRadius)
          .fold<double>(0, (value, radius) => radius > value ? radius : value);
      final radius = cluster.isCluster ? workloadRadius + 4 : workloadRadius;

      if (selected) {
        canvas.drawCircle(
          cluster.screenCenter,
          radius + 5,
          Paint()
            ..color = colorScheme.primary.withValues(alpha: 0.18)
            ..style = PaintingStyle.fill,
        );
      }

      canvas.drawCircle(
        cluster.screenCenter,
        radius,
        Paint()
          ..color = selected ? colorScheme.primary : colorScheme.secondary
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        cluster.screenCenter,
        radius,
        Paint()
          ..color = colorScheme.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      if (cluster.isCluster) {
        final text = TextPainter(
          text: TextSpan(
            text: cluster.members.length.toString(),
            style: TextStyle(
              color: colorScheme.onSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        text.paint(
          canvas,
          cluster.screenCenter -
              Offset(text.width / 2, text.height / 2),
        );
      }
    }
  }

  double _pointRadius(QuadrantTaskPoint point) {
    return switch (point.workload) {
      QuadrantPointWorkload.small => 6,
      QuadrantPointWorkload.medium => 8,
      QuadrantPointWorkload.large => 10,
    };
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder {
    return (Size size) {
      return clusters.map((cluster) {
        final label = cluster.isCluster
            ? '${cluster.members.length} 个任务：${cluster.members.map((e) => e.title).join('，')}'
            : '${cluster.members.single.title}，紧急性 ${cluster.members.single.urgency}，重要性 ${cluster.members.single.importance}';
        return CustomPainterSemantics(
          rect: Rect.fromCircle(
            center: cluster.screenCenter,
            radius: cluster.isCluster ? 18 : 14,
          ),
          properties: SemanticsProperties(
            label: label,
            button: true,
          ),
        );
      }).toList(growable: false);
    };
  }

  @override
  bool shouldRepaint(covariant QuadrantPainter oldDelegate) {
    return oldDelegate.clusters != clusters ||
        oldDelegate.viewport != viewport ||
        oldDelegate.thresholds != thresholds ||
        oldDelegate.selectedTaskId != selectedTaskId ||
        oldDelegate.trajectory != trajectory ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _Label {
  final String text;
  final Offset offset;

  const _Label(this.text, this.offset);
}
