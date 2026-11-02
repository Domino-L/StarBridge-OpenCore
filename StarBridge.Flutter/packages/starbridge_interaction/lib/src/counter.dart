import 'package:flutter/material.dart';

import 'burst.dart';
import 'effect_host.dart';
import 'painters.dart';
import 'suite.dart';

/// A live number. The real value is always the one on screen; effects only
/// accompany the change.
///
/// Normal: rail rolls the old value out and the new one in along the
/// direction of change; scan locks brackets onto the number and leaves a
/// short ▲/▼ mark; glow lights the area behind the number and eases a slight
/// scale back to rest. Standard updates in place.
///
/// Only explicitly passive [coalesceDataUpdates] use continuous state
/// (rapid updates, see [BurstTracker]): rail keeps rolling
/// but each roll is short and starts from where the last one is, never
/// queueing old values; scan holds its brackets and the ▲/▼ mark follows the
/// latest direction; glow keeps one capped light area that brightens a little
/// on each change. When updates stop, the layer settles in 160 ms (scan
/// locks once). Reduced motion: plain in-place updates.
class SuiteCounter extends StatefulWidget {
  const SuiteCounter({
    required this.value,
    this.style,
    this.coalesceDataUpdates = false,
    this.source = InteractionSource.programmatic,
    super.key,
  });

  final int value;
  final TextStyle? style;

  /// Set true for background player counts/statistics. Leave false for
  /// manually edited quantities: every change keeps its full feedback.
  /// A numeric or programmatic value is not automatically passive data.
  final bool coalesceDataUpdates;

  /// Source of the latest change; keyboard edits always land statically.
  final InteractionSource source;

  @override
  State<SuiteCounter> createState() => _SuiteCounterState();
}

class _SuiteCounterState extends State<SuiteCounter>
    with TickerProviderStateMixin {
  /// One value change (roll, mark fade, glow ease).
  late final _t = AnimationController(vsync: this, value: 1);

  /// Presence of the continuous layer.
  late final _flow = AnimationController(vsync: this);
  late final _burst = BurstTracker(vsync: this, onChanged: _onBurst);
  final _fx = GlobalKey<EffectHostState>();
  int? _old;
  bool _up = true;
  double _oldOffset = 0;
  double _oldOpacity = 1;

  @override
  void didUpdateWidget(SuiteCounter old) {
    super.didUpdateWidget(old);
    if (old.coalesceDataUpdates && !widget.coalesceDataUpdates) _settle();
    if (widget.value == old.value) return;
    final data = InteractionScope.of(context);
    if (!data.animates ||
        data.suite == InteractionSuite.standard ||
        widget.source == InteractionSource.keyboard) {
      _settle();
      return;
    }
    // Preserve the still-entering latest digit when it becomes outgoing.
    // Two layers only: no queue and no jump back to the baseline on reversal.
    final wasRolling =
        data.suite == InteractionSuite.rail && _t.value < 1 && _old != null;
    final progress = SuiteMotion.curve.transform(_t.value);
    _oldOffset = wasRolling ? (_up ? 1 : -1) * (1 - progress) : 0;
    _oldOpacity = wasRolling ? progress : 1;
    _up = widget.value > old.value;
    final continuous = widget.coalesceDataUpdates && _burst.hit();
    // Roll from the value currently shown, never replay a queue of values.
    _old = old.value;
    if (continuous) {
      _fx.currentState?.clear();
      _t.duration = data.suite == InteractionSuite.rail
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 220);
      _t.forward(from: 0);
      return;
    }
    _t.duration = switch (data.suite) {
      InteractionSuite.rail => data.motion.select,
      InteractionSuite.scan =>
        data.motion.flash + const Duration(milliseconds: 400),
      _ => data.motion.flash,
    };
    _t.forward(from: 0);
    if (data.suite == InteractionSuite.scan) {
      _fx.currentState?.play(TransientEffect.bracketFlash);
    }
  }

  void _onBurst(bool active) {
    if (!mounted) return;
    final data = InteractionScope.of(context);
    if (!data.animates) return;
    if (active) {
      _flow
        ..duration = BurstMotion.enter
        ..forward();
    } else {
      _flow
        ..duration = BurstMotion.settle
        ..reverse();
      if (data.suite == InteractionSuite.scan) {
        // One short lock to finish, not a full replay of the entrance.
        _fx.currentState?.play(
          TransientEffect.bracketFlash,
          duration: const Duration(milliseconds: 220),
        );
      }
    }
  }

  /// Static final state: latest value, no layers, no running controllers.
  void _settle() {
    _t.value = 1;
    _old = null;
    _burst.reset();
    _flow.value = 0;
    _fx.currentState?.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = InteractionScope.of(context);
    if (!data.animates || data.suite == InteractionSuite.standard) _settle();
  }

  @override
  void dispose() {
    _t.dispose();
    _flow.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final style = (widget.style ?? Theme.of(context).textTheme.headlineSmall!)
        .copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: widget.style?.color ?? p.textPrimary,
        );
    final text = Text('${widget.value}', style: style);
    return Semantics(
      liveRegion: true,
      value: '${widget.value}',
      child: ExcludeSemantics(
        child: EffectHost(
          key: _fx,
          bracketInset: -4,
          bracketLength: 6,
          child: AnimatedBuilder(
            animation: Listenable.merge([_t, _flow]),
            child: text,
            builder: (context, child) {
              final v = _t.value;
              final flow = _flow.value;
              final running = v < 1 && _old != null;
              switch (data.suite) {
                case InteractionSuite.rail when running:
                  final c = SuiteMotion.curve.transform(v);
                  return ClipRect(
                    child: Stack(
                      children: [
                        FractionalTranslation(
                          translation: Offset(0, (_up ? 1 : -1) * (1 - c)),
                          child: Opacity(opacity: c, child: child),
                        ),
                        Positioned.fill(
                          child: FractionalTranslation(
                            translation: Offset(
                              0,
                              _oldOffset + ((_up ? -1 : 1) - _oldOffset) * c,
                            ),
                            child: Opacity(
                              opacity: _oldOpacity * (1 - c),
                              child: Text('${_old!}', style: style),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                case InteractionSuite.scan when running || flow > 0:
                  final markAlpha = flow > 0
                      ? flow
                      : (v < 0.7 ? 1.0 : 1 - (v - 0.7) / 0.3);
                  return CustomPaint(
                    foregroundPainter: flow > 0
                        ? _HeldBrackets(p.edge(flow))
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        child!,
                        const SizedBox(width: 4),
                        Opacity(
                          opacity: markAlpha.clamp(0.0, 1.0),
                          child: Icon(
                            _up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            size: 18,
                            color: _up ? p.success : p.warning,
                          ),
                        ),
                      ],
                    ),
                  );
                case InteractionSuite.glow when running || flow > 0:
                  final k = running ? 1 - SuiteMotion.curve.transform(v) : 0.0;
                  // Continuous: a held, capped glow with a small lift per
                  // change instead of a fresh full pop every time.
                  final alpha = flow > 0 ? 0.22 * flow + 0.12 * k : 0.45 * k;
                  final lift = flow > 0 ? 0.04 * k : 0.12 * k;
                  return CustomPaint(
                    painter: _GlowBehind(p, alpha),
                    child: Transform.scale(scale: 1 + lift, child: child),
                  );
                default:
                  return child!;
              }
            },
          ),
        ),
      ),
    );
  }
}

class _HeldBrackets extends CustomPainter {
  _HeldBrackets(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTWH(0, 0, size.width - 22, size.height);
    paintBrackets(canvas, box.inflate(4), color: color, length: 6);
  }

  @override
  bool shouldRepaint(_HeldBrackets old) => old.color != color;
}

class _GlowBehind extends CustomPainter {
  _GlowBehind(this.p, this.alpha);
  final InteractionPalette p;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 2.2,
      height: size.height * 1.8,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [p.light(alpha), p.light(0)])
            .createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlowBehind old) => old.alpha != alpha;
}
