// Adapted from the approved five-variant startup gallery (2026-08-29).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'startup_motion_spec.dart';

const startupLogoAsset = 'assets/brand/starbridge_mark_transparent.png';
const startupCenterStarAsset = 'assets/brand/starbridge_star_center.png';

class StarBridgeStartupLogo extends StatelessWidget {
  const StarBridgeStartupLogo({
    super.key,
    required this.size,
    this.semanticLabel = 'StarBridge',
  });

  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticLabel,
    excludeSemantics: true,
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          startupLogoAsset,
          key: const ValueKey('startup-logo'),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

/// 严格把原始透明 PNG 视为 5 个语义模块：
/// 1 个完整中心星芒 + 4 条斜向轨迹。
///
/// 加载时，中心星芒按“转一圈—停顿—再转”的节奏独立运动；
/// 四轨保持隐藏，只有真实 Ready 事件到来后才按当前方向的编排淡入归位。
/// 组装完成的下一帧切回单张原图，消除裁切缝并保证最终像素完全一致。
class FivePartBrandLogo extends StatelessWidget {
  const FivePartBrandLogo({
    super.key,
    required this.size,
    required this.revealProgress,
    required this.spin,
    required this.spinTurns,
    required this.assemblyProgress,
    required this.direction,
    required this.reduceMotion,
    required this.lowPerformance,
  });

  final double size;
  final double revealProgress;
  final Animation<double> spin;
  final double spinTurns;
  final double assemblyProgress;
  final StartupMotionDirection direction;
  final bool reduceMotion;
  final bool lowPerformance;

  @override
  Widget build(BuildContext context) {
    final assembled =
        reduceMotion || lowPerformance || assemblyProgress >= .999;
    final finalBlend = ((assemblyProgress - .86) / .14).clamp(0.0, 1.0);
    return Semantics(
      image: true,
      label: 'StarBridge',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          key: const ValueKey('startup-logo'),
          dimension: size,
          child: assembled
              ? Image.asset(
                  startupLogoAsset,
                  key: const ValueKey('startup-brand-settled-image'),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                )
              : Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Opacity(
                      opacity: 1 - finalBlend,
                      child: Stack(
                        key: const ValueKey('startup-brand-modules'),
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          for (final module in const [
                            _LogoModule.trackNorthWest,
                            _LogoModule.trackNorthEast,
                            _LogoModule.trackSouthWest,
                            _LogoModule.trackSouthEast,
                          ])
                            _LogoModuleLayer(
                              module: module,
                              size: size,
                              direction: direction,
                              revealProgress: revealProgress,
                              spinProgress: spin.value,
                              spinTurns: spinTurns,
                              assemblyProgress: assemblyProgress,
                            ),
                          AnimatedBuilder(
                            animation: spin,
                            builder: (context, _) => _LogoModuleLayer(
                              module: _LogoModule.centerStar,
                              size: size,
                              direction: direction,
                              revealProgress: revealProgress,
                              spinProgress: spin.value,
                              spinTurns: spinTurns,
                              assemblyProgress: assemblyProgress,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (finalBlend > 0)
                      Opacity(
                        opacity: finalBlend,
                        child: Image.asset(
                          startupLogoAsset,
                          key: const ValueKey('startup-brand-settled-image'),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

enum _LogoModule {
  centerStar,
  trackNorthWest,
  trackNorthEast,
  trackSouthWest,
  trackSouthEast,
}

class _LogoModuleLayer extends StatelessWidget {
  const _LogoModuleLayer({
    required this.module,
    required this.size,
    required this.direction,
    required this.revealProgress,
    required this.spinProgress,
    required this.spinTurns,
    required this.assemblyProgress,
  });

  final _LogoModule module;
  final double size;
  final StartupMotionDirection direction;
  final double revealProgress;
  final double spinProgress;
  final double spinTurns;
  final double assemblyProgress;

  @override
  Widget build(BuildContext context) {
    return module == _LogoModule.centerStar
        ? _buildCenterStar()
        : _buildTrack();
  }

  Widget _buildCenterStar() {
    final reveal = Curves.easeOutCubic.transform(
      revealProgress.clamp(0.0, 1.0),
    );
    final spinCurve = switch (direction) {
      StartupMotionDirection.soft => Curves.easeInOutSine,
      StartupMotionDirection.clear => const Cubic(.45, 0, .22, 1),
      StartupMotionDirection.technical => const Cubic(.4, 0, .2, 1),
      StartupMotionDirection.tension => const Cubic(.42, 0, .18, 1),
      StartupMotionDirection.spectacular => const Cubic(.5, 0, .1, 1),
    };
    final spinAngle =
        spinCurve.transform(spinProgress.clamp(0.0, 1.0)) *
        math.pi *
        2 *
        spinTurns;
    final assemblyAngle = direction == StartupMotionDirection.tension
        ? -math.sin(math.pi * assemblyProgress.clamp(0.0, 1.0)) * math.pi / 36
        : 0.0;
    final angle = spinAngle + assemblyAngle;
    final scale = .92 + .08 * reveal;

    return Transform.rotate(
      key: const ValueKey('startup-brand-part-star'),
      angle: angle,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: revealProgress.clamp(0.0, 1.0),
          child: Image.asset(
            startupCenterStarAsset,
            key: const ValueKey('startup-brand-star-image'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }

  Widget _buildTrack() {
    final choreography = _TrackChoreography.forModule(direction, module);
    final local = _interval(assemblyProgress, choreography.delay);
    final movement = choreography.curve.transform(local);
    final offset = choreography.offsetAt(size, movement);
    final angle = choreography.startAngle * (1 - movement);
    final scale = _mix(choreography.startScale, 1, movement);
    final opacity = Curves.easeOutCubic.transform(
      _interval(assemblyProgress, choreography.opacityDelay),
    );

    return Transform.translate(
      key: ValueKey(module.keyName),
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        alignment: module.pivotAlignment,
        child: Transform.scale(
          scale: scale,
          alignment: module.pivotAlignment,
          child: Opacity(
            opacity: opacity,
            child: ClipPath(
              clipper: _LogoModuleClipper(module),
              child: _sourceImage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceImage() => Image.asset(
    startupLogoAsset,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    excludeFromSemantics: true,
  );

  double _interval(double value, double delay) =>
      ((value.clamp(0.0, 1.0) - delay) / (1 - delay)).clamp(0.0, 1.0);

  double _mix(double start, double end, double t) => start + (end - start) * t;
}

extension on _LogoModule {
  String get keyName => switch (this) {
    _LogoModule.centerStar => 'startup-brand-part-star',
    _LogoModule.trackNorthWest => 'startup-brand-part-track-nw',
    _LogoModule.trackNorthEast => 'startup-brand-part-track-ne',
    _LogoModule.trackSouthWest => 'startup-brand-part-track-sw',
    _LogoModule.trackSouthEast => 'startup-brand-part-track-se',
  };

  bool get isPrimary =>
      this == _LogoModule.trackNorthEast || this == _LogoModule.trackSouthWest;

  bool get isRight =>
      this == _LogoModule.trackNorthEast || this == _LogoModule.trackSouthEast;

  Alignment get pivotAlignment => switch (this) {
    _LogoModule.centerStar => Alignment.center,
    _LogoModule.trackNorthWest => const Alignment(-.5193, -.2184),
    _LogoModule.trackNorthEast => const Alignment(.4609, -.2162),
    _LogoModule.trackSouthWest => const Alignment(-.4476, .2483),
    _LogoModule.trackSouthEast => const Alignment(.5228, .2301),
  };

  Offset get outwardAxis => switch (this) {
    _LogoModule.centerStar => Offset.zero,
    _LogoModule.trackNorthWest => const Offset(-.831193, .555984),
    _LogoModule.trackNorthEast => const Offset(.883118, -.469151),
    _LogoModule.trackSouthWest => const Offset(-.878979, .476861),
    _LogoModule.trackSouthEast => const Offset(.834369, -.551206),
  };
}

class _TrackChoreography {
  const _TrackChoreography({
    required this.start,
    required this.control,
    required this.delay,
    required this.opacityDelay,
    required this.startAngle,
    required this.startScale,
    required this.curve,
  });

  final Offset start;
  final Offset control;
  final double delay;
  final double opacityDelay;
  final double startAngle;
  final double startScale;
  final Curve curve;

  Offset offsetAt(double size, double t) {
    final remaining = 1 - t;
    return Offset(
      (start.dx * remaining * remaining + 2 * control.dx * remaining * t) *
          size,
      (start.dy * remaining * remaining + 2 * control.dy * remaining * t) *
          size,
    );
  }

  static _TrackChoreography forModule(
    StartupMotionDirection direction,
    _LogoModule module,
  ) {
    final primary = module.isPrimary;
    return switch (direction) {
      // 默认：右侧两轨从右上沿自身斜率进入，左侧两轨从左下进入；
      // 亮色主轨先到，灰色辅轨稍后跟进。
      StartupMotionDirection.soft => _TrackChoreography(
        start: module.outwardAxis * .22,
        control: module.outwardAxis * .09,
        delay: primary ? .08 : .22,
        opacityDelay: primary ? .04 : .18,
        startAngle: 0,
        startScale: .98,
        curve: const Cubic(.22, 1, .36, 1),
      ),
      // 英朗：四轨沿各自真实长轴近乎同拍切入，路径短、落点明确。
      StartupMotionDirection.clear => _TrackChoreography(
        start: module.outwardAxis * .20,
        control: module.outwardAxis * .07,
        delay: primary ? .04 : .09,
        opacityDelay: primary ? .02 : .07,
        startAngle: 0,
        startScale: 1,
        curve: const Cubic(.16, 1, .3, 1),
      ),
      // 科技感：先锁定亮色主轨，再让灰色辅轨补齐相位。
      // 起点、控制点与终点严格共线于每条轨迹在原图中的长轴，
      // 同时不旋转、不缩放，避免线条在归位时产生横向漂移错觉。
      StartupMotionDirection.technical => _TrackChoreography(
        start: module.outwardAxis * .21,
        control: module.outwardAxis * .085,
        delay: primary ? .05 : .38,
        opacityDelay: primary ? .02 : .34,
        startAngle: 0,
        startScale: 1,
        curve: const Cubic(.2, .8, .2, 1),
      ),
      // 张弦释放：四轨先沿自身长轴快速拉近，在最终位置前短暂停住；
      // 灰轨追齐后共同完成最后一小段，不横移、不回弹、不越过落点。
      StartupMotionDirection.tension => _TrackChoreography(
        start: module.outwardAxis * .34,
        control: module.outwardAxis * .20,
        delay: primary ? .02 : .10,
        opacityDelay: primary ? 0 : .06,
        startAngle: 0,
        startScale: 1,
        curve: const _TensionReleaseCurve(),
      ),
      // 炫酷：两组对角轨迹相向超扫，不绕中心旋涡，也不越位回弹。
      StartupMotionDirection.spectacular => _TrackChoreography(
        start: switch (module) {
          _LogoModule.trackNorthWest => const Offset(-.2992, .2002),
          _LogoModule.trackNorthEast => const Offset(.3179, -.1689),
          _LogoModule.trackSouthWest => const Offset(-.3164, .1717),
          _LogoModule.trackSouthEast => const Offset(.3004, -.1984),
          _LogoModule.centerStar => Offset.zero,
        },
        control: switch (module) {
          _LogoModule.trackNorthWest => const Offset(-.1995, .1334),
          _LogoModule.trackNorthEast => const Offset(.2119, -.1126),
          _LogoModule.trackSouthWest => const Offset(-.2110, .1144),
          _LogoModule.trackSouthEast => const Offset(.2002, -.1323),
          _LogoModule.centerStar => Offset.zero,
        },
        delay: primary ? .18 : .06,
        opacityDelay: primary ? .14 : .02,
        startAngle: module.isRight ? .139626 : -.139626,
        startScale: .90,
        curve: const Cubic(.16, 1, .3, 1),
      ),
    };
  }
}

/// 先到达 82% 的近锁定位置，保持一个短拍，再释放剩余 18%。
/// 曲线始终单调且不超过 1，张力来自时间组织而不是回弹或越位。
class _TensionReleaseCurve extends Curve {
  const _TensionReleaseCurve();

  static const _draw = Cubic(.16, 1, .3, 1);
  static const _release = Cubic(.2, .8, .2, 1);

  @override
  double transformInternal(double t) {
    if (t <= .56) return _draw.transform(t / .56) * .82;
    if (t < .72) return .82;
    return .82 + _release.transform((t - .72) / .28) * .18;
  }
}

class _LogoModuleClipper extends CustomClipper<Path> {
  const _LogoModuleClipper(this.module);

  final _LogoModule module;

  @override
  Path getClip(Size size) {
    Offset p(double x, double y) => Offset(x * size.width, y * size.height);

    Path polygon(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    final northWest = polygon([
      p(.132604, .450581),
      p(.142958, .441788),
      p(.223421, .389001),
      p(.368140, .300532),
      p(.388090, .289387),
      p(.391290, .289403),
      p(.389710, .293414),
      p(.340337, .332611),
      p(.172640, .452402),
      p(.133414, .452995),
    ]);
    final northEast = polygon([
      p(.600605, .440815),
      p(.757576, .362812),
      p(.939993, .276742),
      p(.943988, .276757),
      p(.943994, .278362),
      p(.935232, .285558),
      p(.849973, .337545),
      p(.633443, .463407),
      p(.626241, .461773),
      p(.600627, .448040),
    ]);
    final southWest = polygon([
      p(.056016, .742390),
      p(.071957, .731211),
      p(.169188, .671282),
      p(.367330, .553304),
      p(.374520, .550931),
      p(.379321, .550954),
      p(.390531, .554218),
      p(.408150, .564730),
      p(.408167, .569552),
      p(.399410, .577563),
      p(.102303, .725705),
      p(.059216, .744004),
      p(.056021, .743994),
    ]);
    final southEast = polygon([
      p(.607902, .714568),
      p(.619051, .704974),
      p(.831378, .553217),
      p(.852185, .551719),
      p(.870583, .552603),
      p(.869797, .555812),
      p(.735212, .644671),
      p(.624685, .709838),
      p(.609515, .716989),
      p(.607915, .716980),
    ]);
    return switch (module) {
      _LogoModule.centerStar => Path()..addRect(Offset.zero & size),
      _LogoModule.trackNorthWest => northWest,
      _LogoModule.trackNorthEast => northEast,
      _LogoModule.trackSouthWest => southWest,
      _LogoModule.trackSouthEast => southEast,
    };
  }

  @override
  bool shouldReclip(covariant _LogoModuleClipper oldClipper) =>
      oldClipper.module != module;
}
