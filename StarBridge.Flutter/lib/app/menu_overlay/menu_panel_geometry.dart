import 'dart:math' as math;
import 'dart:ui';

/// Logical-pixel geometry, independent of the HUD's module/grid layout rules.
abstract final class MenuPanelGeometry {
  static bool validSize(Size value) =>
      value.width.isFinite &&
      value.height.isFinite &&
      value.width > 0 &&
      value.height > 0;

  static bool validRect(Rect value) =>
      value.left.isFinite &&
      value.top.isFinite &&
      validSize(value.size) &&
      [
        value.left,
        value.top,
        value.width,
        value.height,
      ].every((v) => v.abs() <= 1000000);

  static Rect fit(Rect rect, Size viewport, Size minimum) {
    if (!validSize(viewport)) return Rect.zero;
    // The display clips the desktop, it does not constrain window coordinates.
    // A generous numeric guard protects persistence without introducing edges.
    return Rect.fromLTWH(
      rect.left.clamp(-1000000, 1000000).toDouble(),
      rect.top.clamp(-1000000, 1000000).toDouble(),
      rect.width.clamp(minimum.width, 1000000).toDouble(),
      rect.height.clamp(minimum.height, 1000000).toDouble(),
    );
  }

  /// Explicit recovery only; never called as part of ordinary movement.
  static Rect recover(Rect rect, Size viewport, Size minimum) {
    if (!validSize(viewport)) return Rect.zero;
    final width = math.min(math.max(rect.width, minimum.width), viewport.width);
    final height = math.min(
      math.max(rect.height, minimum.height),
      viewport.height,
    );
    return Rect.fromLTWH(
      (viewport.width - width) / 2,
      (viewport.height - height) / 2,
      width,
      height,
    );
  }

  static Rect move(
    Rect rect,
    Size viewport,
    Size minimum,
    Iterable<Rect> peers,
    double snap,
  ) {
    final fitRect = fit(rect, viewport, minimum);
    final xs = <double>[0, viewport.width - fitRect.width];
    final ys = <double>[0, viewport.height - fitRect.height];
    for (final peer in peers) {
      if (peer.bottom > fitRect.top && peer.top < fitRect.bottom) {
        xs.addAll([
          peer.left,
          peer.right,
          peer.left - fitRect.width,
          peer.right - fitRect.width,
        ]);
      }
      if (peer.right > fitRect.left && peer.left < fitRect.right) {
        ys.addAll([
          peer.top,
          peer.bottom,
          peer.top - fitRect.height,
          peer.bottom - fitRect.height,
        ]);
      }
    }
    return fit(
      Rect.fromLTWH(
        _nearest(fitRect.left, xs, snap),
        _nearest(fitRect.top, ys, snap),
        fitRect.width,
        fitRect.height,
      ),
      viewport,
      minimum,
    );
  }

  static Rect resize(
    Rect rect,
    Size viewport,
    Size minimum,
    Iterable<Rect> peers,
    double snap,
  ) {
    final width = math.max(minimum.width, rect.width);
    final height = math.max(minimum.height, rect.height);
    final xs = <double>[viewport.width];
    final ys = <double>[viewport.height];
    for (final peer in peers) {
      if (peer.bottom > rect.top && peer.top < rect.top + height) {
        xs.addAll([peer.left, peer.right]);
      }
      if (peer.right > rect.left && peer.left < rect.left + width) {
        ys.addAll([peer.top, peer.bottom]);
      }
    }
    return fit(
      Rect.fromLTWH(
        rect.left,
        rect.top,
        _nearest(rect.left + width, xs, snap) - rect.left,
        _nearest(rect.top + height, ys, snap) - rect.top,
      ),
      viewport,
      minimum,
    );
  }

  static double _nearest(
    double value,
    Iterable<double> edges,
    double threshold,
  ) {
    if (threshold <= 0) return value;
    var result = value;
    var distance = threshold;
    for (final edge in edges) {
      final gap = (value - edge).abs();
      if (gap <= distance) {
        result = edge;
        distance = gap;
      }
    }
    return result;
  }
}
