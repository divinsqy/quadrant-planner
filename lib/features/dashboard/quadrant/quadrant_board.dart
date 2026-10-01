import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/planning/planner_candidate.dart';
import 'quadrant_clusterer.dart';
import 'quadrant_models.dart';
import 'quadrant_painter.dart';
import 'quadrant_viewport.dart';
import 'task_trajectory_builder.dart';

class QuadrantBoard extends StatefulWidget {
  final List<TaskPlanningSnapshot> tasks;
  final QuadrantThresholds thresholds;
  final String? selectedTaskId;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onOpen;
  final ValueChanged<QuadrantThresholds>? onThresholdChanged;
  final List<TaskTrajectoryPoint> trajectory;

  const QuadrantBoard({
    super.key,
    required this.tasks,
    required this.thresholds,
    this.selectedTaskId,
    this.onSelect,
    this.onOpen,
    this.onThresholdChanged,
    this.trajectory = const [],
  });

  @override
  State<QuadrantBoard> createState() => _QuadrantBoardState();
}

enum _DragMode {
  none,
  urgencyThreshold,
  importanceThreshold,
  pan,
}

class _QuadrantBoardState extends State<QuadrantBoard> {
  static const EdgeInsets _plotPadding = EdgeInsets.fromLTRB(36, 28, 28, 32);
  static const double _clusterRadius = 14;
  static const double _hitRadius = 20;

  final FocusNode _focusNode = FocusNode(debugLabel: 'quadrant-board');
  QuadrantViewport _viewport = const QuadrantViewport();
  late QuadrantThresholds _thresholds = widget.thresholds.clamped();
  QuadrantCluster? _hovered;
  List<QuadrantCluster> _clusters = const [];
  QuadrantHitTestIndex? _hitIndex;
  Size _size = Size.zero;
  _DragMode _dragMode = _DragMode.none;
  String? _localSelectedTaskId;
  Offset? _doubleTapPosition;

  String? get _selectedTaskId =>
      widget.selectedTaskId ?? _localSelectedTaskId;

  @override
  void didUpdateWidget(covariant QuadrantBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thresholds != widget.thresholds &&
        _dragMode == _DragMode.none) {
      _thresholds = widget.thresholds.clamped();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _updateGeometry(
    Size size,
    List<QuadrantCluster> clusters,
  ) {
    _size = size;
    _clusters = clusters;
    _hitIndex = QuadrantHitTestIndex(
      clusters: clusters,
      cellSize: 40,
    );
  }

  QuadrantCluster? _hit(Offset position) {
    return _hitIndex?.hitTest(position, radiusPx: _hitRadius);
  }

  void _handleHover(PointerHoverEvent event) {
    final hit = _hit(event.localPosition);
    if (identical(hit, _hovered)) {
      return;
    }
    setState(() {
      _hovered = hit;
    });
  }

  void _handleTapUp(TapUpDetails details) {
    _focusNode.requestFocus();
    final hit = _hit(details.localPosition);
    if (hit == null || hit.members.isEmpty) {
      return;
    }
    final id = hit.members.first.id;
    setState(() {
      _localSelectedTaskId = id;
    });
    widget.onSelect?.call(id);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    final position = _doubleTapPosition;
    if (position == null) {
      return;
    }
    final hit = _hit(position);
    if (hit != null && hit.members.isNotEmpty) {
      final id = hit.members.first.id;
      setState(() {
        _localSelectedTaskId = id;
      });
      widget.onOpen?.call(id);
      return;
    }

    setState(() {
      _viewport = const QuadrantViewport();
    });
  }

  void _handlePanStart(DragStartDetails details) {
    _focusNode.requestFocus();
    final position = details.localPosition;
    final thresholdScreen = _viewport.dataToScreen(
      Offset(
        _thresholds.urgency.toDouble(),
        _thresholds.importance.toDouble(),
      ),
      _size,
      _plotPadding,
    );

    if ((position.dx - thresholdScreen.dx).abs() <= 10) {
      _dragMode = _DragMode.urgencyThreshold;
    } else if ((position.dy - thresholdScreen.dy).abs() <= 10) {
      _dragMode = _DragMode.importanceThreshold;
    } else {
      _dragMode = _DragMode.pan;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_size.isEmpty) {
      return;
    }

    switch (_dragMode) {
      case _DragMode.urgencyThreshold:
        final data = _viewport.screenToData(
          details.localPosition,
          _size,
          _plotPadding,
        );
        final next = _thresholds.copyWith(urgency: data.dx.round());
        if (next != _thresholds) {
          setState(() => _thresholds = next);
          widget.onThresholdChanged?.call(next);
        }
      case _DragMode.importanceThreshold:
        final data = _viewport.screenToData(
          details.localPosition,
          _size,
          _plotPadding,
        );
        final next = _thresholds.copyWith(importance: data.dy.round());
        if (next != _thresholds) {
          setState(() => _thresholds = next);
          widget.onThresholdChanged?.call(next);
        }
      case _DragMode.pan:
        final rect = _viewport.plotRect(_size, _plotPadding);
        final span = _viewport.visibleSpan;
        final dx = rect.width == 0
            ? 0.0
            : -details.delta.dx / rect.width * span;
        final dy = rect.height == 0
            ? 0.0
            : details.delta.dy / rect.height * span;
        setState(() {
          _viewport = _viewport.panByData(Offset(dx, dy));
        });
      case _DragMode.none:
        break;
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    _dragMode = _DragMode.none;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final factor = event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15;
    setState(() {
      _viewport = _viewport.zoomBy(factor);
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      final id = _selectedTaskId ??
          (_clusters.isEmpty || _clusters.first.members.isEmpty
              ? null
              : _clusters.first.members.first.id);
      if (id != null) {
        widget.onOpen?.call(id);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final ids = _clusters
          .expand((cluster) => cluster.members)
          .map((point) => point.id)
          .toList(growable: false);
      if (ids.isEmpty) {
        return KeyEventResult.ignored;
      }
      final current = ids.indexOf(_selectedTaskId ?? '');
      final forward = event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowDown;
      final nextIndex = current < 0
          ? 0
          : (current + (forward ? 1 : -1) + ids.length) % ids.length;
      final id = ids[nextIndex];
      setState(() => _localSelectedTaskId = id);
      widget.onSelect?.call(id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.tasks
        .map(QuadrantTaskPoint.fromSnapshot)
        .toList(growable: false);
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 400,
          );
          final clusters = const QuadrantClusterer().cluster(
            points: points,
            viewport: _viewport,
            size: size,
            padding: _plotPadding,
            radiusPx: _clusterRadius,
          );
          _updateGeometry(size, clusters);

          return MouseRegion(
            key: const ValueKey('quadrant-board-focus'),
            onHover: _handleHover,
            onExit: (_) {
              if (_hovered != null) {
                setState(() => _hovered = null);
              }
            },
            child: Listener(
              onPointerSignal: _handlePointerSignal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleTapUp,
                onDoubleTapDown: _handleDoubleTapDown,
                onDoubleTap: _handleDoubleTap,
                onPanStart: _handlePanStart,
                onPanUpdate: _handlePanUpdate,
                onPanEnd: _handlePanEnd,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: QuadrantPainter(
                          clusters: clusters,
                          viewport: _viewport,
                          thresholds: _thresholds,
                          padding: _plotPadding,
                          selectedTaskId: _selectedTaskId,
                          trajectory: widget.trajectory,
                          colorScheme: scheme,
                        ),
                      ),
                    ),
                    if (_hovered != null)
                      _HoverCard(
                        cluster: _hovered!,
                        canvasSize: size,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HoverCard extends StatelessWidget {
  final QuadrantCluster cluster;
  final Size canvasSize;

  const _HoverCard({
    required this.cluster,
    required this.canvasSize,
  });

  @override
  Widget build(BuildContext context) {
    const width = 240.0;
    final desiredLeft = cluster.screenCenter.dx + 14;
    final desiredTop = cluster.screenCenter.dy + 14;
    final left = desiredLeft.clamp(8.0, (canvasSize.width - width - 8).clamp(8.0, double.infinity));
    final top = desiredTop.clamp(8.0, (canvasSize.height - 150).clamp(8.0, double.infinity));

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: IgnorePointer(
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: cluster.isCluster
                ? _ClusterDetails(cluster: cluster)
                : _TaskDetails(point: cluster.members.single),
          ),
        ),
      ),
    );
  }
}

class _TaskDetails extends StatelessWidget {
  final QuadrantTaskPoint point;

  const _TaskDetails({
    required this.point,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          point.title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text('紧急性 ${point.urgency} · 重要性 ${point.importance}'),
        if (point.description.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            point.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        for (final entry in point.metadata.entries.take(3))
          Text('${entry.key}：${entry.value}'),
      ],
    );
  }
}

class _ClusterDetails extends StatelessWidget {
  final QuadrantCluster cluster;

  const _ClusterDetails({
    required this.cluster,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${cluster.members.length} 个任务',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        for (final point in cluster.members.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              point.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
