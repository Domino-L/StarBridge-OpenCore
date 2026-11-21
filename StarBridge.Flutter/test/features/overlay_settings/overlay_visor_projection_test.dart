import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_projection.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import 'overlay_settings_ux_a_test.dart' show settings;

/// The Dart camera against the visor's: a white members-sized box drawn through
/// the real D2D PerspectiveTransform3D with OverlayVisorRenderer.Place's
/// settings (hinge at the group's edge, origin the screen centre, depth 1000 x
/// screen scale), its edges measured from the pixels (11-11, both sides, 0, 15
/// and 40 degrees, 1920x1080 and 2560x1440). Vertical edges stay vertical; each
/// row gives the box and the measured left and right edges with their tops and
/// bottoms.
void main() {
  const fixture = [
    (
      w: 1920,
      h: 1080,
      right: true,
      deg: 0,
      box: Rect.fromLTWH(1671.00, 386.00, 193.00, 209.00),
      left: 1671.00,
      rightX: 1864.00,
      leftTop: 386.00,
      leftBottom: 595.00,
      rightTop: 386.00,
      rightBottom: 595.00,
    ),
    (
      w: 1920,
      h: 1080,
      right: true,
      deg: 15,
      box: Rect.fromLTWH(1671.00, 386.00, 193.00, 209.00),
      left: 1636.00,
      rightX: 1852.89,
      leftTop: 395.22,
      leftBottom: 591.71,
      rightTop: 388.28,
      rightBottom: 594.18,
    ),
    (
      w: 1920,
      h: 1080,
      right: true,
      deg: 40,
      box: Rect.fromLTWH(1671.00, 386.00, 193.00, 209.00),
      left: 1623.13,
      rightX: 1845.00,
      leftTop: 407.01,
      leftBottom: 587.47,
      rightTop: 391.55,
      rightBottom: 593.00,
    ),
    (
      w: 1920,
      h: 1080,
      right: false,
      deg: 0,
      box: Rect.fromLTWH(56.00, 386.00, 193.00, 209.00),
      left: 56.00,
      rightX: 249.00,
      leftTop: 386.00,
      leftBottom: 595.00,
      rightTop: 386.00,
      rightBottom: 595.00,
    ),
    (
      w: 1920,
      h: 1080,
      right: false,
      deg: 15,
      box: Rect.fromLTWH(56.00, 386.00, 193.00, 209.00),
      left: 67.11,
      rightX: 284.00,
      leftTop: 388.28,
      leftBottom: 594.18,
      rightTop: 395.22,
      rightBottom: 591.71,
    ),
    (
      w: 1920,
      h: 1080,
      right: false,
      deg: 40,
      box: Rect.fromLTWH(56.00, 386.00, 193.00, 209.00),
      left: 75.00,
      rightX: 296.87,
      leftTop: 391.55,
      leftBottom: 593.00,
      rightTop: 407.01,
      rightBottom: 587.47,
    ),
    (
      w: 2560,
      h: 1440,
      right: true,
      deg: 0,
      box: Rect.fromLTWH(2228.00, 514.67, 257.33, 278.67),
      left: 2228.00,
      rightX: 2485.00,
      leftTop: 514.67,
      leftBottom: 793.33,
      rightTop: 514.67,
      rightBottom: 793.33,
    ),
    (
      w: 2560,
      h: 1440,
      right: true,
      deg: 15,
      box: Rect.fromLTWH(2228.00, 514.67, 257.33, 278.67),
      left: 2181.25,
      rightX: 2470.51,
      leftTop: 526.80,
      leftBottom: 789.18,
      rightTop: 517.67,
      rightBottom: 792.31,
    ),
    (
      w: 2560,
      h: 1440,
      right: true,
      deg: 40,
      box: Rect.fromLTWH(2228.00, 514.67, 257.33, 278.67),
      left: 2164.17,
      rightX: 2459.87,
      leftTop: 542.74,
      leftBottom: 783.30,
      rightTop: 521.78,
      rightBottom: 791.12,
    ),
    (
      w: 2560,
      h: 1440,
      right: false,
      deg: 0,
      box: Rect.fromLTWH(74.67, 514.67, 257.33, 278.67),
      left: 75.00,
      rightX: 332.00,
      leftTop: 514.67,
      leftBottom: 793.33,
      rightTop: 514.67,
      rightBottom: 793.33,
    ),
    (
      w: 2560,
      h: 1440,
      right: false,
      deg: 15,
      box: Rect.fromLTWH(74.67, 514.67, 257.33, 278.67),
      left: 89.49,
      rightX: 378.75,
      leftTop: 517.67,
      leftBottom: 792.31,
      rightTop: 526.80,
      rightBottom: 789.18,
    ),
    (
      w: 2560,
      h: 1440,
      right: false,
      deg: 40,
      box: Rect.fromLTWH(74.67, 514.67, 257.33, 278.67),
      left: 100.13,
      rightX: 395.83,
      leftTop: 521.78,
      leftBottom: 791.12,
      rightTop: 542.74,
      rightBottom: 783.30,
    ),
  ];
  for (final f in fixture) {
    test('${f.w}x${f.h} ${f.right ? 'right' : 'left'} ${f.deg} degrees', () {
      final q = OverlayVisorProjection.quad(
        f.box,
        right: f.right,
        degrees: f.deg.toDouble(),
        surface: Size(f.w.toDouble(), f.h.toDouble()),
      );
      // top left, top right, bottom right, bottom left
      void near(Offset p, double x, double y, String what) {
        expect(p.dx, closeTo(x, 0.75), reason: '$what x');
        expect(p.dy, closeTo(y, 0.75), reason: '$what y');
      }

      near(q[0], f.left, f.leftTop, 'top left');
      near(q[3], f.left, f.leftBottom, 'bottom left');
      near(q[1], f.rightX, f.rightTop, 'top right');
      near(q[2], f.rightX, f.rightBottom, 'bottom right');
    });
  }

  test('no tilt changes nothing', () {
    final box = const Rect.fromLTWH(1671, 386, 193, 209);
    expect(
      OverlayVisorProjection.quad(
        box,
        right: true,
        degrees: 0,
        surface: const Size(1920, 1080),
      ),
      [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft],
    );
  });

  test('a shown point goes back to the flat point it came from', () {
    for (final right in [true, false]) {
      for (final deg in [0.0, 15.0, 40.0]) {
        for (final p in const [
          Offset(1671, 386),
          Offset(60, 900),
          Offset(1200, 150),
        ]) {
          final shown = OverlayVisorProjection.point(
            p,
            right: right,
            degrees: deg,
            surface: const Size(1920, 1080),
          );
          final back = OverlayVisorProjection.unproject(
            shown,
            right: right,
            degrees: deg,
            surface: const Size(1920, 1080),
          );
          expect(back.dx, closeTo(p.dx, 1e-6));
          expect(back.dy, closeTo(p.dy, 1e-6));
        }
      }
    }
  });

  // review CX-VISOR-EVENTS3D-R2: on a very wide screen at 40 degrees the right
  // side's vanishing line (x near 88) is on screen; a pointer past it is held
  // just before it, so the flat point stays finite and keeps its direction
  test('a pointer past the vanishing line stays finite and in order', () {
    const surface = Size(2560, 1080);
    double flatX(double x) => OverlayVisorProjection.unproject(
      Offset(x, 540),
      right: true,
      degrees: 40,
      surface: surface,
    ).dx;
    var last = double.infinity;
    for (final x in [800.0, 300.0, 120.0, 95.0, 89.0, 88.0, 60.0, 0.0]) {
      final flat = flatX(x);
      expect(flat.isFinite, isTrue, reason: 'x $x');
      expect(flat, lessThanOrEqualTo(last), reason: 'x $x keeps the order');
      last = flat;
    }
  });

  // review CX-VISOR-EVENTS3D-R3: across the middle the block is drawn by the
  // camera of the side its centre is on, and that drawing jumps; a pointer
  // swept across keeps the grabbed point as near as the drawing allows, on a
  // block always drawn by its own side's camera, with one jump only
  for (final (surface, degrees) in [
    (const Size(1920, 1080), 15.0),
    (const Size(2560, 1080), 40.0),
  ]) {
    test('dragging across the middle at $degrees on $surface', () {
      const box = Rect.fromLTWH(1400, 300, 364, 394);
      final grab = box.center;
      final mid = surface.width / 2;
      double? gap;
      var jumps = 0;
      Offset? last;
      for (var x = mid - 200; x <= mid + 200; x += 1) {
        final pointer = Offset(x, 520);
        final move = OverlayVisorProjection.follow(
          grab,
          box,
          pointer,
          degrees: degrees,
          surface: surface,
        );
        final landed = box.shift(move);
        final right = landed.center.dx > mid;
        final shown = OverlayVisorProjection.point(
          grab + move,
          right: right,
          degrees: degrees,
          surface: surface,
        );
        expect(shown.dx.isFinite && shown.dy.isFinite, isTrue);
        expect((shown.dy - pointer.dy).abs(), lessThan(1e-6), reason: 'x $x');
        final miss = (shown.dx - pointer.dx).abs();
        if (miss > 1e-6) {
          // in the gap: the block sits at the middle on the nearer side
          expect((landed.center.dx - mid).abs(), lessThanOrEqualTo(0.5001));
          gap ??=
              OverlayVisorProjection.point(
                Offset(mid + 0.5, grab.dy),
                right: true,
                degrees: degrees,
                surface: surface,
              ).dx -
              OverlayVisorProjection.point(
                Offset(mid - 0.5, grab.dy),
                right: false,
                degrees: degrees,
                surface: surface,
              ).dx;
          expect(miss, lessThanOrEqualTo(gap / 2 + 1), reason: 'x $x');
        }
        if (last != null && (shown - last).distance > 10) jumps++;
        last = shown;
      }
      expect(gap, isNotNull, reason: 'the sweep crosses the gap');
      expect(jumps, 1, reason: "the drawing's own jump, once");
    });
  }

  // 11-11 viewing distance (视距): the camera at 600, 1000 and 3000 against
  // the renderer's single-camera formula (OverlayVisorRenderer.SpacePoint, the
  // D2D-checked geometry above at 1000), both sides, 0/15/40 degrees
  group('viewing distance', () {
    Offset space(bool right, Offset p, double deg, double dist, Size s) {
      final depth = dist * s.height / 1080;
      final hinge = right ? s.width : 0.0;
      final d = (p.dx - hinge).abs();
      final a = deg * math.pi / 180;
      final x1 = right ? hinge - d * math.cos(a) : d * math.cos(a);
      final f = depth / (depth + d * math.sin(a));
      final cx = s.width / 2, cy = s.height / 2;
      return Offset(cx + (x1 - cx) * f, cy + (p.dy - cy) * f);
    }

    for (final surface in const [Size(1920, 1080), Size(2560, 1440)]) {
      for (final dist in [600.0, 1000.0, 3000.0]) {
        for (final deg in [0.0, 15.0, 40.0]) {
          for (final right in [true, false]) {
            test(
              '$surface distance $dist, $deg degrees, ${right ? 'right' : 'left'}',
              () {
                for (final u in [20.0, 180.0, 420.0]) {
                  for (final y in [
                    80.0,
                    surface.height / 2,
                    surface.height - 60,
                  ]) {
                    final p = Offset(right ? surface.width - u : u, y);
                    final shown = OverlayVisorProjection.point(
                      p,
                      right: right,
                      degrees: deg,
                      surface: surface,
                      distance: dist,
                    );
                    final want = space(right, p, deg, dist, surface);
                    expect((shown - want).distance, lessThan(1e-6));
                    final back = OverlayVisorProjection.unproject(
                      shown,
                      right: right,
                      degrees: deg,
                      surface: surface,
                      distance: dist,
                    );
                    expect((back - p).distance, lessThan(1e-6));
                  }
                }
              },
            );
          }
        }
      }
    }

    test('nearer is a stronger perspective; no lean, no change', () {
      const surface = Size(1920, 1080);
      const p = Offset(1700, 300);
      double x(double dist, double deg) => OverlayVisorProjection.point(
        p,
        right: true,
        degrees: deg,
        surface: surface,
        distance: dist,
      ).dx;
      expect(x(600, 40), lessThan(x(1000, 40)));
      expect(x(1000, 40), lessThan(x(3000, 40)));
      expect(x(600, 0), closeTo(p.dx, 1e-9));
      expect(x(3000, 0), closeTo(p.dx, 1e-9));
    });

    test('the setting reads 1000 when absent and stays in 600-3000', () {
      // a Host from before the setting sends no such field
      final older = OverlayWorkspaceSettings.fromMap(
        settings().toMap()..remove('visorViewingDistance'),
      );
      expect(older['visorViewingDistance'], 1000.0);
      expect(OverlayVisorProjection.distance(older), 1000);
      expect(
        OverlayVisorProjection.distance(
          settings().withValue('visorViewingDistance', 1650.0),
        ),
        1650,
      );
      expect(
        OverlayVisorProjection.distance(
          settings().withValue('visorViewingDistance', 3000.0),
        ),
        3000,
      );
      // the settings refuse a value outside the range (the Host clamps saves)
      expect(
        () => settings().withValue('visorViewingDistance', 9000.0),
        throwsFormatException,
      );
    });
  });
}
