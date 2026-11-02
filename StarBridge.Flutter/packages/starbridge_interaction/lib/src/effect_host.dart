import 'package:flutter/widgets.dart';

import 'painters.dart';
import 'suite.dart';

/// One-shot decorations that run over a control and then disappear.
enum TransientEffect {
  /// Scan: a soft band sweeps left to right.
  beam,

  /// Scan: a 2 px line passes top to bottom.
  scanLine,

  /// Scan: corner brackets close in from outside, hold, then fade.
  bracketFlash,

  /// Glow: one expanding ring from a point.
  ring,

  /// Rail: a light band travels along the row after a data update.
  sweep,

  /// Glow: an inset edge and fill that light up, then fade.
  pulse,
}

/// Hosts [TransientEffect]s for its child. Playing an effect that is already
/// running restarts it; effects never queue. Reduced motion skips them and
/// clears any that are running.
///
/// The decorations are painted in front of the child and never take hits.
class EffectHost extends StatefulWidget {
  const EffectHost({
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.bracketInset = 0,
    this.bracketLength = 7,
    this.boundsResolver,
    this.paintExclusionResolver,
    super.key,
  });

  final Widget child;

  /// Clip for beam, scan line, sweep and pulse. Rings and brackets may
  /// extend past the bounds.
  final BorderRadius borderRadius;

  /// Final inset of the bracket flash (negative draws outside the bounds).
  final double bracketInset;
  final double bracketLength;

  /// Optional paint-only bounds for decorations around an existing native
  /// input container. No layout, hit-test, focus or value ownership changes.
  final Rect Function(Size size)? boundsResolver;
  final Rect? Function()? paintExclusionResolver;

  static EffectHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<EffectHostState>();

  @override
  State<EffectHost> createState() => EffectHostState();
}

class EffectHostState extends State<EffectHost> with TickerProviderStateMixin {
  final _controllers = <TransientEffect, AnimationController>{};
  final _repaint = _Repaint();
  Offset? _ringCenter;
  double _ringScale = 3.2;
  Color? _ringColor;
  Color? _tint;

  /// Plays [effect]. [at] is the ring centre in local coordinates (defaults
  /// to the centre). [duration] overrides the suite default (e.g. the short
  /// lock that ends a continuous state). [color] overrides the effect colour (rings, brackets,
  /// sweep and pulse), e.g. success or danger tones.
  void play(
    TransientEffect effect, {
    Offset? at,
    Color? color,
    double ringScale = 3.2,
    Duration? duration,
  }) {
    if (!mounted) return;
    final data = InteractionScope.of(context);
    if (!data.animates) return;
    final m = data.motion;
    final length =
        duration ??
        switch (effect) {
          TransientEffect.beam || TransientEffect.scanLine => m.sweep,
          TransientEffect.bracketFlash => m.flash,
          TransientEffect.ring => m.ring,
          TransientEffect.sweep || TransientEffect.pulse => m.flash,
        };
    if (length == Duration.zero) return;
    if (effect == TransientEffect.ring) {
      _ringCenter = at;
      _ringScale = ringScale;
      _ringColor = color;
    }
    if (effect != TransientEffect.ring) _tint = color;
    final c = _controllers.putIfAbsent(
      effect,
      () => AnimationController(vsync: this)..addListener(_repaint.ping),
    );
    c.duration = length;
    c.forward(from: 0);
  }

  /// Stops and removes every running effect.
  void clear() {
    for (final c in _controllers.values) {
      c.reset();
    }
    _repaint.ping();
  }

  double _t(TransientEffect e) => _controllers[e]?.value ?? 0;

  @visibleForTesting
  bool isPlaying(TransientEffect effect) =>
      _controllers[effect]?.isAnimating ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) clear();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    return CustomPaint(
      foregroundPainter: _EffectPainter(this, data.palette, _repaint),
      child: widget.child,
    );
  }
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _EffectPainter extends CustomPainter {
  _EffectPainter(this.host, this.palette, Listenable repaint)
    : super(repaint: repaint);

  final EffectHostState host;
  final InteractionPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds =
        host.widget.boundsResolver?.call(size) ?? (Offset.zero & size);
    canvas.save();
    clipPaintExclusion(
      canvas,
      size,
      host.widget.paintExclusionResolver?.call(),
    );
    final rrect = host.widget.borderRadius.toRRect(bounds);
    final beam = host._t(TransientEffect.beam);
    final scan = host._t(TransientEffect.scanLine);
    final sweep = host._t(TransientEffect.sweep);
    final pulse = host._t(TransientEffect.pulse);
    Color tint(double a) => host._tint == null
        ? palette.light(a)
        : host._tint!.withValues(alpha: palette.isDark ? a : a * 0.75);
    if (_running(beam) ||
        _running(scan) ||
        _running(sweep) ||
        _running(pulse)) {
      canvas.save();
      canvas.clipRRect(rrect);
      if (_running(sweep)) {
        final band = bounds.width * 0.45;
        final x = bounds.left - band + (bounds.width + band * 1.6) * sweep;
        final r = Rect.fromLTWH(x, 0, band, size.height);
        canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(colors: [tint(0), tint(0.38), tint(0)])
                .createShader(r),
        );
        paintSideBar(
          canvas,
          bounds,
          (host._tint ?? palette.accentBright).withValues(alpha: 1 - sweep),
          inset: 9,
        );
      }
      if (_running(pulse)) {
        final k = 1 - pulse;
        canvas.drawRRect(rrect, Paint()..color = tint(0.24 * k));
        canvas.drawRRect(
          rrect.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = (host._tint ?? palette.accentBright).withValues(
              alpha: 0.9 * k,
            ),
        );
      }
      if (_running(beam)) {
        paintBeam(
          canvas,
          bounds,
          const Cubic(0.2, 0, 0, 1).transform(beam),
          palette.isDark
              ? const Color(0xFFAAE4FF).withValues(alpha: 0.75)
              : palette.accent.withValues(alpha: 0.32),
        );
      }
      if (_running(scan)) {
        paintScanLine(
          canvas,
          bounds,
          const Cubic(0.2, 0, 0, 1).transform(scan),
          palette.edge(),
        );
      }
      canvas.restore();
    }
    final brackets = host._t(TransientEffect.bracketFlash);
    if (_running(brackets)) {
      final inset = host.widget.bracketInset;
      final grow = (brackets / 0.35).clamp(0.0, 1.0);
      final alpha = brackets < 0.35 ? 1.0 : 1 - (brackets - 0.35) / 0.65;
      paintBrackets(
        canvas,
        bounds.deflate(
          inset - 5 * (1 - const Cubic(0.2, 0, 0, 1).transform(grow)),
        ),
        color: (host._tint ?? palette.edge()).withValues(alpha: alpha),
        length: host.widget.bracketLength,
      );
    }
    final ring = host._t(TransientEffect.ring);
    if (_running(ring)) {
      paintRing(
        canvas,
        host._ringCenter ?? bounds.center,
        ring,
        host._ringColor ?? palette.edge(),
        maxScale: host._ringScale,
      );
    }
    canvas.restore();
  }

  static bool _running(double t) => t > 0 && t < 1;

  @override
  bool shouldRepaint(_EffectPainter old) => old.palette != palette;
}
