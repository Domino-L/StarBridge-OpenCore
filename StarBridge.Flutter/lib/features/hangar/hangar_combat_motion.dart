import 'package:flutter/animation.dart';

enum HangarCombatSize {
  small(1600, 11.5, 15),
  medium(1800, 8, 8),
  large(2000, 9, 15),
  capital(2200, 10, 10);

  const HangarCombatSize(this.milliseconds, this.ammoTravel, this.muzzleHeight);
  final int milliseconds;
  final double ammoTravel, muzzleHeight;
  static HangarCombatSize? parse(Object? value) {
    for (final size in values) {
      if (size.name == value) return size;
    }
    return null;
  }
}

class CombatPartFrame {
  const CombatPartFrame(
    this.offset, {
    this.x = 0,
    this.y = 0,
    this.sx = 1,
    this.sy = 1,
    this.alpha = 1,
    this.easing = Curves.linear,
  });
  final double offset, x, y, sx, sy, alpha;
  final Curve easing;
}

/// The approved Web Animations timeline, in original 32-unit coordinates.
abstract final class HangarCombatMotion {
  static const assemblyCurve = Cubic(.22, .7, .22, 1);
  static const ammoCurve = Cubic(.36, .08, .24, 1);
  static const snapCurve = Cubic(.68, 0, .84, .45);
  static double firingAt(HangarCombatSize size) =>
      (1380 + 220 * .24) * size.milliseconds / 1600;

  static CombatPartFrame part(HangarCombatSize size, int part, double ms) {
    final factor = size.milliseconds / 1600;
    if (part == 0) {
      return _sample(ms, 0, 680 * factor, const [
        CombatPartFrame(0, y: 7, sx: .96, sy: .96, alpha: 0),
        CombatPartFrame(.45, y: 2.5, sx: .985, sy: .985, alpha: .6),
        CombatPartFrame(.83, y: -.2),
        CombatPartFrame(1),
      ], assemblyCurve);
    }
    if (part == 1 || part == 2) {
      final x = part == 1 ? -7.0 : 7.0;
      final y = size == HangarCombatSize.small ? 3.0 : 2.0;
      return _sample(ms, 320 * factor, 860 * factor, [
        CombatPartFrame(0, x: x, y: y, alpha: 0),
        CombatPartFrame(.36, x: x * .45, y: y * .45, alpha: .65),
        CombatPartFrame(
          .56,
          x: x * .36,
          y: y * .36,
          alpha: .75,
          easing: snapCurve,
        ),
        CombatPartFrame(.8, x: -x * .06),
        const CombatPartFrame(1),
      ], assemblyCurve);
    }
    return _sample(ms, 840 * factor, 540 * factor, const [
      CombatPartFrame(0, y: 4, alpha: 0),
      CombatPartFrame(.55, y: 1.2, alpha: .7),
      CombatPartFrame(.84, y: -.24),
      CombatPartFrame(1),
    ], assemblyCurve);
  }

  static CombatPartFrame recoil(HangarCombatSize size, double ms) => _sample(
    ms,
    1380 * size.milliseconds / 1600,
    220 * size.milliseconds / 1600,
    const [
      CombatPartFrame(0, easing: Cubic(.2, .75, .3, 1)),
      CombatPartFrame(
        .24,
        y: .65,
        sx: 1.04,
        sy: .975,
        easing: Cubic(.15, .85, .3, 1),
      ),
      CombatPartFrame(.62, y: -.15, sx: .995, sy: 1.01),
      CombatPartFrame(1),
    ],
    Curves.linear,
  );

  static double ammoY(HangarCombatSize size, double ms) =>
      size.ammoTravel *
      (1 - ammoCurve.transform(((ms - firingAt(size)) / 140).clamp(0.0, 1.0)));

  static CombatPartFrame _sample(
    double ms,
    double delay,
    double duration,
    List<CombatPartFrame> frames,
    Curve effectCurve,
  ) {
    final progress = effectCurve.transform(
      ((ms - delay) / duration).clamp(0.0, 1.0),
    );
    if (progress <= 0) return frames.first;
    if (progress >= 1) return frames.last;
    // Keep exact keyframe poses despite floating-point phase division.
    for (final frame in frames) {
      if ((progress - frame.offset).abs() < 1e-9) return frame;
    }
    var right = 1;
    while (frames[right].offset < progress) {
      right++;
    }
    final a = frames[right - 1], b = frames[right];
    final t = a.easing.transform((progress - a.offset) / (b.offset - a.offset));
    double mix(double start, double end) => start + (end - start) * t;
    return CombatPartFrame(
      progress,
      x: mix(a.x, b.x),
      y: mix(a.y, b.y),
      sx: mix(a.sx, b.sx),
      sy: mix(a.sy, b.sy),
      alpha: mix(a.alpha, b.alpha),
    );
  }
}
