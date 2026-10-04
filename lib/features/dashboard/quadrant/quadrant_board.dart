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
  final Map<String, Map<String, String>> taskMetadata;

  const QuadrantBoard({
    super.key,
    required this.tasks,
    required this.thresholds,
    this.selectedTaskId,
    this.onSelect,
    this.onOpen,
    this.onThresholdChanged,
    this.trajectory = const [],
    this.taskMetadata = const {},
  });

  @override
  State<QuadrantBoard> createState() => _QuadrantBoardState();
}

enum _DragMode { none, urgencyThreshold, importanceThreshold, pan }

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
  QuadrantViewport? _geometryViewport;
  List<QuadrantTaskPoint>? _points;
  bool _geometryDirty = true;
  _DragMode _dragMode = _DragMode.none;
  String? _localSelectedTaskId;
  String? _focusedTaskId;
  String? _expandedClusterTaskId;
  Rect? _clusterPickerRect;
  Rect? _metadataRect;
  Duration? _lastClickTime;
  Offset? _lastClickPosition;
  String? _lastClickTaskId;
  bool _lastClickWasEmpty = false;

  String? get _selectedTaskId => widget.selectedTaskId ?? _localSelectedTaskId;

  String? get _activeTaskId =>
      _focusNode.hasFocus ? _focusedTaskId ?? _selectedTaskId : _selectedTaskId;

  @override
  void didUpdateWidget(covariant QuadrantBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks ||
        oldWidget.taskMetadata != widget.taskMetadata) {
      _points = null;
      _geometryDirty = true;
    }
    if (oldWidget.thresholds != widget.thresholds &&
        _dragMode == _DragMode.none) {
      _thresholds = widget.thresholds.clamped();
    }
    if (oldWidget.selectedTaskId != widget.selectedTaskId) {
      _localSelectedTaskId = widget.selectedTaskId;
      _focusedTaskId = widget.selectedTaskId;
    }
    if (!widget.tasks.any((snapshot) => snapshot.task.id == _focusedTaskId)) {
      _focusedTaskId = null;
    }
    if (!widget.tasks.any(
      (snapshot) => snapshot.task.id == _expandedClusterTaskId,
    )) {
      _expandedClusterTaskId = null;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _updateGeometry(Size size, List<QuadrantCluster> clusters) {
    _size = size;
    _clusters = clusters;
    _hitIndex = QuadrantHitTestIndex(clusters: clusters, cellSize: 40);
  }

  QuadrantCluster? _hit(Offset position) {
    return _hitIndex?.hitTest(position, radiusPx: _hitRadius);
  }

  void _handleHover(PointerHoverEvent event) {
    if (_metadataRect?.contains(event.localPosition) ?? false) return;
    final hit = _hit(event.localPosition);
    if (identical(hit, _hovered)) {
      return;
    }
    setState(() {
      _hovered = hit;
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    // The lazy member picker owns its gestures; they must not drag the plot.
    if ((_clusterPickerRect?.contains(event.localPosition) ?? false) ||
        (_metadataRect?.contains(event.localPosition) ?? false)) {
      return;
    }
    _focusNode.requestFocus();
    _beginPointerDrag(event.localPosition);

    final hit = _hit(event.localPosition);
    final id = hit == null || hit.members.isEmpty ? null : hit.members.first.id;

    final isDoubleClick = _isDoubleClick(
      time: event.timeStamp,
      position: event.localPosition,
      taskId: id,
    );

    if (id != null) {
      _selectTask(id);
      setState(() => _expandedClusterTaskId = hit!.isCluster ? id : null);
      if (isDoubleClick) {
        widget.onOpen?.call(id);
      }
    } else if (isDoubleClick) {
      setState(() {
        _viewport = const QuadrantViewport();
        _expandedClusterTaskId = null;
      });
    } else {
      setState(() => _expandedClusterTaskId = null);
    }

    _rememberClick(
      time: event.timeStamp,
      position: event.localPosition,
      taskId: id,
    );
  }

  bool _isDoubleClick({
    required Duration time,
    required Offset position,
    required String? taskId,
  }) {
    final previousTime = _lastClickTime;
    final previousPosition = _lastClickPosition;
    if (previousTime == null || previousPosition == null) {
      return false;
    }

    final elapsed = time - previousTime;
    if (elapsed.isNegative ||
        elapsed > const Duration(milliseconds: 350) ||
        (position - previousPosition).distance > 18) {
      return false;
    }

    if (taskId != null) {
      return !_lastClickWasEmpty && _lastClickTaskId == taskId;
    }
    return _lastClickWasEmpty;
  }

  void _rememberClick({
    required Duration time,
    required Offset position,
    required String? taskId,
  }) {
    _lastClickTime = time;
    _lastClickPosition = position;
    _lastClickTaskId = taskId;
    _lastClickWasEmpty = taskId == null;
  }

  void _beginPointerDrag(Offset position) {
    if (_size.isEmpty) {
      _dragMode = _DragMode.none;
      return;
    }
    final thresholdScreen = _viewport.dataToScreen(
      Offset(_thresholds.urgency.toDouble(), _thresholds.importance.toDouble()),
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

  void _handlePointerMove(PointerMoveEvent event) {
    if (_size.isEmpty || _dragMode == _DragMode.none) {
      return;
    }

    switch (_dragMode) {
      case _DragMode.urgencyThreshold:
        final data = _viewport.screenToData(
          event.localPosition,
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
          event.localPosition,
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
        final dx = rect.width == 0 ? 0.0 : -event.delta.dx / rect.width * span;
        final dy = rect.height == 0 ? 0.0 : event.delta.dy / rect.height * span;
        setState(() {
          _viewport = _viewport.panByData(Offset(dx, dy));
        });
      case _DragMode.none:
        break;
    }
  }

  void _handlePointerUp(PointerEvent event) {
    _dragMode = _DragMode.none;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_metadataRect?.contains(event.localPosition) ?? false) return;
    if (event is! PointerScrollEvent) {
      return;
    }
    if (_clusterPickerRect?.contains(event.localPosition) ?? false) {
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
      final id =
          _activeTaskId ??
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
      final current = ids.indexOf(_activeTaskId ?? '');
      final forward =
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowDown;
      final nextIndex = current < 0
          ? 0
          : (current + (forward ? 1 : -1) + ids.length) % ids.length;
      final id = ids[nextIndex];
      _selectTask(id);
      setState(() {
        _hovered = null;
        _expandedClusterTaskId = null;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _expandedClusterTaskId != null) {
      setState(() => _expandedClusterTaskId = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectTask(String id) {
    _focusNode.requestFocus();
    setState(() {
      _localSelectedTaskId = id;
      _focusedTaskId = id;
    });
    widget.onSelect?.call(id);
  }

  void _openTask(String id) {
    _selectTask(id);
    widget.onOpen?.call(id);
  }

  void _activateCluster(QuadrantCluster cluster) {
    _selectTask(cluster.members.first.id);
    setState(() {
      _expandedClusterTaskId = cluster.isCluster
          ? cluster.members.first.id
          : null;
    });
  }

  void _handleFocusChange(bool focused) {
    setState(() {
      if (focused) {
        _focusedTaskId ??=
            _selectedTaskId ??
            (_clusters.isEmpty ? null : _clusters.first.members.first.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = _points ??= widget.tasks
        .map(
          (snapshot) => QuadrantTaskPoint.fromSnapshot(
            snapshot,
            extraMetadata: widget.taskMetadata[snapshot.task.id] ?? const {},
          ),
        )
        .toList(growable: false);
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      onFocusChange: _handleFocusChange,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 400,
          );
          if (_geometryDirty ||
              _size != size ||
              _geometryViewport != _viewport) {
            final hoveredId = _hovered?.members.first.id;
            final clusters = const QuadrantClusterer().cluster(
              points: points,
              viewport: _viewport,
              size: size,
              padding: _plotPadding,
              radiusPx: _clusterRadius,
            );
            _updateGeometry(size, clusters);
            _geometryViewport = _viewport;
            _geometryDirty = false;
            _hovered = hoveredId == null
                ? null
                : clusters
                      .where((c) => c.members.any((p) => p.id == hoveredId))
                      .firstOrNull;
          }
          final clusters = _clusters;
          QuadrantCluster? expanded;
          QuadrantCluster? focused;
          for (final cluster in clusters) {
            for (final point in cluster.members) {
              if (point.id == _expandedClusterTaskId) {
                expanded = cluster;
              }
              if (_focusNode.hasFocus && point.id == _focusedTaskId) {
                focused = QuadrantCluster(
                  members: [point],
                  screenCenter: cluster.screenCenter,
                );
              }
            }
          }
          _clusterPickerRect = expanded == null
              ? null
              : _pickerRect(expanded, size);
          final details = _hovered ?? focused;
          _metadataRect = expanded == null && details != null
              ? _metadataCardRect(details, size)
              : null;

          return MouseRegion(
            key: const ValueKey('quadrant-board-focus'),
            onHover: _handleHover,
            onExit: (_) {
              if (_hovered != null) {
                setState(() => _hovered = null);
              }
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerUp,
              onPointerSignal: _handlePointerSignal,
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
                        selectedTaskId: _activeTaskId,
                        trajectory: widget.trajectory,
                        colorScheme: scheme,
                        onActivateCluster: _activateCluster,
                        onOpenTask: _openTask,
                      ),
                    ),
                  ),
                  if (_focusNode.hasFocus)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.primary, width: 2),
                          ),
                        ),
                      ),
                    ),
                  if (expanded != null)
                    _ClusterPicker(
                      cluster: expanded,
                      rect: _clusterPickerRect!,
                      selectedTaskId: _activeTaskId,
                      onSelect: _selectTask,
                      onOpen: _openTask,
                    )
                  else if (details != null)
                    _HoverCard(cluster: details, rect: _metadataRect!),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Rect _pickerRect(QuadrantCluster cluster, Size size) {
  return _detailsCardRect(cluster, size, maxWidth: 260, maxHeight: 260);
}

class _ClusterPicker extends StatelessWidget {
  final QuadrantCluster cluster;
  final Rect rect;
  final String? selectedTaskId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;

  const _ClusterPicker({
    required this.cluster,
    required this.rect,
    required this.selectedTaskId,
    required this.onSelect,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: ListView.builder(
          key: const ValueKey('quadrant-cluster-members'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cluster.members.length,
          itemBuilder: (context, index) {
            final point = cluster.members[index];
            return Semantics(
              button: true,
              selected: point.id == selectedTaskId,
              label: point.semanticsLabel,
              hint: '单击预览，双击打开详情',
              onTap: () => onSelect(point.id),
              onLongPress: () => onOpen(point.id),
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('quadrant-cluster-member-${point.id}'),
                onTap: () => onSelect(point.id),
                onDoubleTap: () => onOpen(point.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: _TaskDetails(point: point),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HoverCard extends StatelessWidget {
  final QuadrantCluster cluster;
  final Rect rect;

  const _HoverCard({required this.cluster, required this.rect});

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: Material(
        elevation: 6,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: cluster.isCluster
              ? _ClusterDetails(cluster: cluster)
              : _TaskDetails(point: cluster.members.single),
        ),
      ),
    );
  }
}

Rect _metadataCardRect(QuadrantCluster cluster, Size size) {
  return _detailsCardRect(cluster, size, maxWidth: 240, maxHeight: 280);
}

Rect _detailsCardRect(
  QuadrantCluster cluster,
  Size size, {
  required double maxWidth,
  required double maxHeight,
}) {
  const gap = 24.0;
  final rightSpace = size.width - 8 - cluster.screenCenter.dx - gap;
  final leftSpace = cluster.screenCenter.dx - gap - 8;
  final placeRight = rightSpace >= maxWidth || rightSpace >= leftSpace;
  // Keep the originating point's hit area clear, including in narrow boards.
  final width = (placeRight ? rightSpace : leftSpace)
      .clamp(1.0, maxWidth)
      .toDouble();
  final height = (size.height - 16).clamp(1.0, maxHeight).toDouble();
  final left =
      (placeRight
              ? cluster.screenCenter.dx + gap
              : cluster.screenCenter.dx - gap - width)
          .clamp(8.0, (size.width - width - 8).clamp(8.0, double.infinity))
          .toDouble();
  final top = (cluster.screenCenter.dy + 14)
      .clamp(8.0, (size.height - height - 8).clamp(8.0, double.infinity))
      .toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

class _TaskDetails extends StatelessWidget {
  final QuadrantTaskPoint point;

  const _TaskDetails({required this.point});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(point.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text('紧急性 ${point.urgency} · 重要性 ${point.importance}'),
        if (point.description.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(point.description, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        for (final entry in point.metadata.entries)
          Text('${entry.key}：${entry.value}'),
      ],
    );
  }
}

class _ClusterDetails extends StatelessWidget {
  final QuadrantCluster cluster;

  const _ClusterDetails({required this.cluster});

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
