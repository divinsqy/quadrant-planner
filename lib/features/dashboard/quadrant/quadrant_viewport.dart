import 'dart:ui';

import 'package:flutter/painting.dart';

class QuadrantViewport {
  final Offset center;
  final double zoom;

  const QuadrantViewport({
    this.center = const Offset(50, 50),
    this.zoom = 1,
  }) : assert(zoom > 0);

  double get visibleSpan => 100 / zoom;

  QuadrantViewport zoomBy(double factor) {
    final nextZoom = (zoom * factor).clamp(1.0, 8.0);
    return QuadrantViewport(
      center: _clampCenter(center, nextZoom),
      zoom: nextZoom,
    );
  }

  QuadrantViewport panByData(Offset delta) {
    return QuadrantViewport(
      center: _clampCenter(center + delta, zoom),
      zoom: zoom,
    );
  }

  Offset dataToScreen(
    Offset data,
    Size size,
    EdgeInsets padding,
  ) {
    final rect = _plotRect(size, padding);
    final span = visibleSpan;
    final minX = center.dx - span / 2;
    final minY = center.dy - span / 2;
    final nx = (data.dx - minX) / span;
    final ny = (data.dy - minY) / span;

    return Offset(
      rect.left + nx * rect.width,
      rect.bottom - ny * rect.height,
    );
  }

  Offset screenToData(
    Offset screen,
    Size size,
    EdgeInsets padding,
  ) {
    final rect = _plotRect(size, padding);
    final span = visibleSpan;
    final minX = center.dx - span / 2;
    final minY = center.dy - span / 2;

    final nx = rect.width == 0 ? 0.5 : (screen.dx - rect.left) / rect.width;
    final ny = rect.height == 0 ? 0.5 : (rect.bottom - screen.dy) / rect.height;

    return Offset(
      (minX + nx * span).clamp(0.0, 100.0),
      (minY + ny * span).clamp(0.0, 100.0),
    );
  }

  Rect plotRect(Size size, EdgeInsets padding) => _plotRect(size, padding);

  static Offset _clampCenter(Offset value, double zoom) {
    final half = 50 / zoom;
    return Offset(
      value.dx.clamp(half, 100 - half),
      value.dy.clamp(half, 100 - half),
    );
  }

  static Rect _plotRect(Size size, EdgeInsets padding) {
    final width = (size.width - padding.horizontal).clamp(1.0, double.infinity);
    final height =
        (size.height - padding.vertical).clamp(1.0, double.infinity);
    return Rect.fromLTWH(
      padding.left,
      padding.top,
      width,
      height,
    );
  }
}
