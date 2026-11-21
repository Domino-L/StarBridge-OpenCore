import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'overlay_visor_arrange.dart';
import 'overlay_visor_layout.dart';
import 'overlay_workspace_models.dart';

/// The visor's camera for its side groups (StarBridge.Desktop
/// OverlayVisorRenderer.Place), so the editors show and hit the blocks where
/// the visor draws them (user, 11-11: "要用同样的3d效果").
///
/// Each side group (members, events, chat) turns about a vertical axis on its
/// screen edge by the tilt setting (right side: -degrees, left: +degrees); the
/// perspective origin is the screen centre and the depth the viewing distance
/// (design units of a 1080-high screen: 1000 unless set). A point at distance d from the
/// edge recedes by d * sin(tilt) and is scaled toward the centre by
/// depth / (depth + d * sin(tilt)). Checked against the D2D
/// PerspectiveTransform3D the visor uses (both sides, 0, 15 and 40 degrees).
///
/// Placing and saving stay flat (the layout boxes), as in the visor itself;
/// only what is shown and hit is projected.
abstract final class OverlayVisorProjection {
  /// The viewing distance a visor has without the setting (and had before it
  /// was adjustable), in design units of a 1080-high screen.
  static const double viewingDistance = 1000;

  /// The viewing distance setting (视距, 600 to 3000, 1000 by default; 11-11
  /// user: "浮层外观应该让视距也可调"): nearer is a stronger perspective.
  static double distance(OverlayWorkspaceSettings settings) =>
      ((settings['visorViewingDistance'] as num?)?.toDouble() ??
              viewingDistance)
          .clamp(600.0, 3000.0)
          .toDouble();

  /// The tilt setting in degrees (0 to 60, 15 by default; 40 until 11-14).
  static double degrees(OverlayWorkspaceSettings settings) =>
      ((settings['visorTilt'] as num?)?.toDouble() ?? 15)
          .clamp(0.0, 60.0)
          .toDouble();

  /// The visor groups drawn tilted and the side each leans to (true: right).
  /// Empty unless the visor is the shown appearance.
  static Map<String, bool> tilts(
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) => OverlayVisorLayout.active(settings)
      ? OverlayVisorArrange.tilts(layout, settings, surface)
      : const {};

  /// The camera in surface pixels: a flat point (z = 0) to where it shows.
  static Matrix4 matrix({
    required bool right,
    required double degrees,
    required Size surface,
    double distance = viewingDistance,
  }) {
    final depth = distance * surface.height / 1080;
    final hinge = right ? surface.width : 0.0;
    final cx = surface.width / 2, cy = surface.height / 2;
    final angle = (right ? -degrees : degrees) * 3.141592653589793 / 180;
    final perspective = Matrix4.identity()..setEntry(3, 2, -1 / depth);
    return Matrix4.translationValues(cx, cy, 0)
      ..multiply(perspective)
      ..multiply(Matrix4.translationValues(-cx, -cy, 0))
      ..multiply(Matrix4.translationValues(hinge, 0, 0))
      ..multiply(Matrix4.rotationY(angle))
      ..multiply(Matrix4.translationValues(-hinge, 0, 0));
  }

  /// Where a flat point shows.
  static Offset point(
    Offset p, {
    required bool right,
    required double degrees,
    required Size surface,
    double distance = viewingDistance,
  }) => MatrixUtils.transformPoint(
    matrix(
      right: right,
      degrees: degrees,
      surface: surface,
      distance: distance,
    ),
    p,
  );

  /// The least 1 / w a shown point is taken back from (a flat point at most
  /// ten times as deep as the screen).
  static const double minimumW = 0.1;

  /// The flat point that shows at [shown]: the camera undone on the flat
  /// layer (z = 0), where it is a 3 x 3 homography. A drag follows the pointer
  /// one to one on screen by moving the flat block by the difference of the
  /// pointer's flat points (review CX-VISOR-EVENTS3D-R1).
  static Offset unproject(
    Offset shown, {
    required bool right,
    required double degrees,
    required Size surface,
    double distance = viewingDistance,
  }) {
    final m = matrix(
      right: right,
      degrees: degrees,
      surface: surface,
      distance: distance,
    );
    double e(int row, int column) => m.entry(row, column);
    final a = e(0, 0), b = e(0, 1), c = e(0, 3);
    final d = e(1, 0), f = e(1, 1), g = e(1, 3);
    final h = e(3, 0), i = e(3, 1), j = e(3, 3);
    // the inverse by cofactors; its third row over the determinant is 1 / the
    // camera's w of the flat point: 1 at no lean, falling toward 0 at the
    // vanishing line (reachable on a very wide screen at 40 degrees) and
    // negative behind it. A pointer past the line where it is [minimumW] is
    // held on that line, so the flat point stays finite and on the right side
    // of the camera (review CX-VISOR-EVENTS3D-R2).
    final det = a * (f * j - g * i) - b * (d * j - g * h) + c * (d * i - f * h);
    final wx = (d * i - f * h) / det, wy = (b * h - a * i) / det;
    final w0 = (a * f - b * d) / det;
    var p = shown;
    if (!(wx * p.dx + wy * p.dy + w0 >= minimumW) && wx.abs() > 1e-12) {
      p = Offset((minimumW - wy * p.dy - w0) / wx, p.dy);
    }
    final x = (f * j - g * i) * p.dx + (c * i - b * j) * p.dy + (b * g - c * f);
    final y = (g * h - d * j) * p.dx + (a * j - c * h) * p.dy + (c * d - a * g);
    final w = (wx * p.dx + wy * p.dy + w0) * det;
    return Offset(x / w, y / w);
  }

  /// The flat move that puts the flat point [grab] of a block (its flat box
  /// [box] when the drag began) under the pointer shown at [pointer]. Taken
  /// from where the pointer is each time, never added up, so crossing the
  /// middle (where the lean turns) cannot leave the block off the pointer: the
  /// camera is the one of the side the block lands on (review
  /// CX-VISOR-EVENTS3D-R2).
  static Offset follow(
    Offset grab,
    Rect box,
    Offset pointer, {
    required double degrees,
    required Size surface,
    double distance = viewingDistance,
  }) {
    Offset to(bool right) =>
        unproject(
          pointer,
          right: right,
          degrees: degrees,
          surface: surface,
          distance: distance,
        ) -
        grab;
    bool lands(Offset move) => box.shift(move).center.dx > surface.width / 2;
    // the side the pointer is on first: a camera far from the pointer may hold
    // it at its vanishing line and so never carry the block across
    final side = pointer.dx > surface.width / 2;
    final move = to(side);
    if (lands(move) == side) return move;
    final other = to(!side);
    if (lands(other) == !side) return other;
    // Neither lands on its own camera's side: the pointer is in the gap the
    // visor's drawing jumps across at the middle (a block just left of it
    // shows well left of one just right of it). Hold the block's centre just
    // on each side in turn, its grabbed point at the pointer's height, and
    // keep the one whose grabbed point shows nearer the pointer: each side
    // follows on continuously and the only jump is the drawing's own, half
    // way across the gap (review CX-VISOR-EVENTS3D-R3).
    Offset held(bool right) {
      final cx = surface.width / 2 + (right ? 0.5 : -0.5);
      final dx = cx - box.center.dx;
      final flatX = grab.dx + dx;
      final y = flatY(
        pointer.dy,
        flatX,
        right: right,
        degrees: degrees,
        surface: surface,
        distance: distance,
      );
      return Offset(dx, y - grab.dy);
    }

    double miss(bool right, Offset move) =>
        (point(
                  grab + move,
                  right: right,
                  degrees: degrees,
                  surface: surface,
                  distance: distance,
                ) -
                pointer)
            .distance;
    final mine = held(side), theirs = held(!side);
    return miss(!side, theirs) < miss(side, mine) ? theirs : mine;
  }

  /// The flat height of a point at flat [flatX] that shows at [shownY]: a
  /// point's height shows scaled toward the centre by its depth, which only
  /// its distance from the hinge sets. For the events, pinned to a screen edge,
  /// whose grabbed point keeps its place on the block while the pointer may be
  /// anywhere across the screen (review CX-VISOR-EVENTS3D-R2).
  static double flatY(
    double shownY,
    double flatX, {
    required bool right,
    required double degrees,
    required Size surface,
    double distance = viewingDistance,
  }) {
    final depth = distance * surface.height / 1080;
    final reach = (right ? surface.width - flatX : flatX).abs();
    final sin = math.sin(degrees * math.pi / 180);
    final cy = surface.height / 2;
    return cy + (shownY - cy) * (depth + reach * sin) / depth;
  }

  /// A flat box's shown corners: top left, top right, bottom right, bottom
  /// left.
  static List<Offset> quad(
    Rect box, {
    required bool right,
    required double degrees,
    required Size surface,
    double distance = viewingDistance,
  }) => [
    for (final corner in [
      box.topLeft,
      box.topRight,
      box.bottomRight,
      box.bottomLeft,
    ])
      point(
        corner,
        right: right,
        degrees: degrees,
        surface: surface,
        distance: distance,
      ),
  ];

  /// The transform for a widget laid out flat at [box] (surface pixels) on a
  /// canvas drawn at [scaleX] x [scaleY] canvas pixels per surface pixel: the
  /// widget's own coordinates to its parent's. Hit testing follows it, so a
  /// click lands where the block shows.
  static Matrix4 forWidget(
    Rect box, {
    required bool right,
    required double degrees,
    required Size surface,
    double distance = viewingDistance,
    double scaleX = 1,
    double scaleY = 1,
  }) {
    final ox = box.left * scaleX, oy = box.top * scaleY;
    return Matrix4.translationValues(-ox, -oy, 0)
      ..multiply(Matrix4.diagonal3Values(scaleX, scaleY, 1))
      ..multiply(
        matrix(
          right: right,
          degrees: degrees,
          surface: surface,
          distance: distance,
        ),
      )
      ..multiply(Matrix4.diagonal3Values(1 / scaleX, 1 / scaleY, 1))
      ..multiply(Matrix4.translationValues(ox, oy, 0));
  }
}
