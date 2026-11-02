import 'package:flutter/animation.dart';

import 'official_fleet_holo_paint.dart';

/// Entry phases of the main-fleet holo header, created once per header
/// (CurvedAnimation listens to the controller; building them per frame would
/// leak listeners).
///
/// Full, the first visit of the day (2.4 s, a small ceremony):
/// the seam under the banner powers on from the centre, the banner is unveiled
/// along the client slant, a scan passes down the mirror deck as its light and
/// reflection come up, the glass slab slides in, the fleet code is traced
/// letter-band by letter-band, the numbers count up, and one glint closes it.
///
/// Quick, later visits (0.42 s): the same final state, short and close.
class OfficialFleetHoloTimeline {
  OfficialFleetHoloTimeline(AnimationController entry, {required this.quick})
    : slabOffset = quick ? -10 : -28 {
    Animation<double> at(
      int start,
      int length, [
      Curve curve = Curves.easeOut,
    ]) {
      final animation = officialFleetHoloPhase(
        entry,
        quick ? officialFleetHoloQuickMs : officialFleetHoloFullMs,
        start,
        length,
        curve,
      );
      _owned.add(animation);
      return animation;
    }

    const done = AlwaysStoppedAnimation(1.0);
    const idle = AlwaysStoppedAnimation(0.0);
    if (quick) {
      seam = done;
      unveil = done;
      ambient = at(0, 300);
      mirror = at(0, 300);
      scan = idle;
      slab = at(0, 380, officialFleetHoloSettle);
      edge = at(100, 280);
      code = at(0, 320, Curves.easeOutCubic);
      _stats = [
        for (var i = 0; i < 3; i++)
          at(80 + 30 * i, 320, officialFleetHoloSettle),
      ];
      glint = idle;
    } else {
      seam = at(0, 420, Curves.easeOutCubic);
      unveil = at(250, 800, Curves.easeInOutCubic);
      // The banner's light and reflection only follow once it is shown.
      ambient = at(900, 800);
      mirror = at(950, 600);
      scan = at(1000, 650, Curves.easeInOut);
      slab = at(1000, 550, officialFleetHoloSettle);
      edge = at(1200, 450);
      code = at(1250, 800, Curves.easeInOutCubic);
      _stats = [
        for (var i = 0; i < 3; i++)
          at(1350 + 80 * i, 700, officialFleetHoloSettle),
      ];
      glint = at(1950, 450, Curves.easeInOut);
    }
  }

  final bool quick;
  final double slabOffset;
  final _owned = <Animation<double>>[];
  late final Animation<double> seam;
  late final Animation<double> unveil;
  late final Animation<double> ambient;
  late final Animation<double> mirror;
  late final Animation<double> scan;
  late final Animation<double> slab;
  late final Animation<double> edge;
  late final Animation<double> code;
  late final Animation<double> glint;
  late final List<Animation<double>> _stats;

  /// Numbers count up only on the full entry.
  bool get countUp => !quick;

  Animation<double> stat(int index) => _stats[index.clamp(0, 2)];

  void dispose() {
    for (final animation in _owned) {
      if (animation is CurvedAnimation) animation.dispose();
    }
  }
}
