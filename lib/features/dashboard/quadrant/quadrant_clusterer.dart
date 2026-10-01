import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';

import 'quadrant_models.dart';
import 'quadrant_viewport.dart';

class QuadrantClusterer {
  const QuadrantClusterer();

  List<QuadrantCluster> cluster({
    required List<QuadrantTaskPoint> points,
    required QuadrantViewport viewport,
    required Size size,
    required EdgeInsets padding,
    required double radiusPx,
  }) {
    if (points.isEmpty) {
      return const [];
    }
    if (radiusPx <= 0) {
      throw ArgumentError.value(radiusPx, 'radiusPx', 'must be positive');
    }

    final positions = points
        .map(
          (point) => viewport.dataToScreen(
            Offset(point.urgency.toDouble(), point.importance.toDouble()),
            size,
            padding,
          ),
        )
        .toList(growable: false);

    final parents = List<int>.generate(points.length, (index) => index);
    final grid = <_Cell, List<int>>{};
    final cellSize = radiusPx;

    int find(int value) {
      var root = value;
      while (parents[root] != root) {
        root = parents[root];
      }
      var cursor = value;
      while (parents[cursor] != cursor) {
        final next = parents[cursor];
        parents[cursor] = root;
        cursor = next;
      }
      return root;
    }

    void union(int a, int b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) {
        parents[rootB] = rootA;
      }
    }

    for (var index = 0; index < points.length; index += 1) {
      final position = positions[index];
      final cell = _Cell.fromOffset(position, cellSize);

      for (var dx = -1; dx <= 1; dx += 1) {
        for (var dy = -1; dy <= 1; dy += 1) {
          final neighbors = grid[_Cell(cell.x + dx, cell.y + dy)];
          if (neighbors == null) {
            continue;
          }
          for (final other in neighbors) {
            if ((positions[other] - position).distance <= radiusPx) {
              union(index, other);
            }
          }
        }
      }

      grid.putIfAbsent(cell, () => <int>[]).add(index);
    }

    final grouped = <int, List<int>>{};
    for (var index = 0; index < points.length; index += 1) {
      grouped.putIfAbsent(find(index), () => <int>[]).add(index);
    }

    final clusters = grouped.values.map((indices) {
      var sumX = 0.0;
      var sumY = 0.0;
      for (final index in indices) {
        sumX += positions[index].dx;
        sumY += positions[index].dy;
      }
      return QuadrantCluster(
        members: List.unmodifiable(indices.map((index) => points[index])),
        screenCenter: Offset(sumX / indices.length, sumY / indices.length),
      );
    }).toList()
      ..sort((a, b) {
        final x = a.screenCenter.dx.compareTo(b.screenCenter.dx);
        return x != 0 ? x : a.screenCenter.dy.compareTo(b.screenCenter.dy);
      });

    return List.unmodifiable(clusters);
  }
}

class QuadrantHitTestIndex {
  final double cellSize;
  final Map<_Cell, List<QuadrantCluster>> _grid = {};

  QuadrantHitTestIndex({
    required List<QuadrantCluster> clusters,
    required this.cellSize,
  }) {
    if (cellSize <= 0) {
      throw ArgumentError.value(cellSize, 'cellSize', 'must be positive');
    }
    for (final cluster in clusters) {
      final cell = _Cell.fromOffset(cluster.screenCenter, cellSize);
      _grid.putIfAbsent(cell, () => <QuadrantCluster>[]).add(cluster);
    }
  }

  QuadrantCluster? hitTest(
    Offset position, {
    required double radiusPx,
  }) {
    final cell = _Cell.fromOffset(position, cellSize);
    QuadrantCluster? best;
    var bestDistance = double.infinity;
    final reach = math.max(1, (radiusPx / cellSize).ceil());

    for (var dx = -reach; dx <= reach; dx += 1) {
      for (var dy = -reach; dy <= reach; dy += 1) {
        final clusters = _grid[_Cell(cell.x + dx, cell.y + dy)];
        if (clusters == null) {
          continue;
        }
        for (final cluster in clusters) {
          final distance = (cluster.screenCenter - position).distance;
          if (distance <= radiusPx && distance < bestDistance) {
            best = cluster;
            bestDistance = distance;
          }
        }
      }
    }
    return best;
  }
}

class _Cell {
  final int x;
  final int y;

  const _Cell(this.x, this.y);

  factory _Cell.fromOffset(Offset value, double cellSize) {
    return _Cell(
      (value.dx / cellSize).floor(),
      (value.dy / cellSize).floor(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _Cell && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}
