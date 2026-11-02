import 'package:flutter/material.dart';

import 'effect_host.dart';
import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

/// Animates a change of [icon] (favourite on/off, copy → copied, show/hide
/// password). The icon glyphs themselves are never altered or blurred.
///
/// Rail: the old icon slides out upward and the new one slides in from
/// below (a short hand-off along one axis). Scan: the new icon locks in with
/// a brief flicker and small corner brackets. Glow: the spot lights up, then
/// the new icon pops in. Standard swaps directly. [instant] (keyboard) and
/// reduced motion swap without animation.
class SuiteIconSwap extends StatefulWidget {
  const SuiteIconSwap({
    required this.icon,
    this.size = 18,
    this.color,
    this.instant = false,
    super.key,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final bool instant;

  @override
  State<SuiteIconSwap> createState() => _SuiteIconSwapState();
}

class _SuiteIconSwapState extends State<SuiteIconSwap>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, value: 1);
  final _fx = GlobalKey<EffectHostState>();
  IconData? _old;

  @override
  void didUpdateWidget(SuiteIconSwap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon == widget.icon) return;
    final data = InteractionScope.of(context);
    if (!data.animates ||
        widget.instant ||
        data.suite == InteractionSuite.standard) {
      _t.value = 1;
      _old = null;
      _fx.currentState?.clear();
      return;
    }
    // A new swap interrupts the previous one; it never queues.
    _old = oldWidget.icon;
    _t.duration = switch (data.suite) {
      InteractionSuite.scan => const Duration(milliseconds: 260),
      InteractionSuite.glow => const Duration(milliseconds: 280),
      _ => data.motion.select - const Duration(milliseconds: 60),
    };
    _t.forward(from: 0);
    if (data.suite == InteractionSuite.scan) {
      _fx.currentState?.play(
        TransientEffect.bracketFlash,
        duration: const Duration(milliseconds: 420),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) {
      _t.value = 1;
      _old = null;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  static const _flicker = [0.0, 1.0, 0.25, 1.0, 0.6, 1.0];

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final color = widget.color ?? IconTheme.of(context).color;
    Widget glyph(IconData i) => Icon(i, size: widget.size, color: color);
    return EffectHost(
      key: _fx,
      bracketInset: -3,
      bracketLength: 4,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final v = _t.value;
            final old = _old;
            if (v >= 1 || old == null) return glyph(widget.icon);
            final c = SuiteMotion.curve.transform(v);
            switch (data.suite) {
              case InteractionSuite.rail:
                return ClipRect(
                  child: Stack(
                    children: [
                      FractionalTranslation(
                        translation: Offset(0, -0.6 * c),
                        child: Opacity(opacity: 1 - c, child: glyph(old)),
                      ),
                      FractionalTranslation(
                        translation: Offset(0, 0.6 * (1 - c)),
                        child: Opacity(opacity: c, child: glyph(widget.icon)),
                      ),
                    ],
                  ),
                );
              case InteractionSuite.scan:
                final step = (v * (_flicker.length - 1)).floor();
                return Opacity(
                  opacity: _flicker[step.clamp(0, _flicker.length - 1)],
                  child: glyph(widget.icon),
                );
              case InteractionSuite.glow:
                // First light the spot (old icon fades), then the new pops.
                final light = v < 0.4 ? v / 0.4 : 1 - (v - 0.4) / 0.6;
                final pop = v < 0.4
                    ? 0.0
                    : SuiteMotion.curve.transform((v - 0.4) / 0.6);
                final scale = v < 0.4
                    ? 1.0
                    : (pop < 0.6
                          ? 0.7 + pop / 0.6 * 0.4
                          : 1.1 - (pop - 0.6) / 0.4 * 0.1);
                return CustomPaint(
                  painter: _SpotPainter(p, 0.45 * light),
                  child: v < 0.4
                      ? Opacity(opacity: 1 - v / 0.4, child: glyph(old))
                      : Transform.scale(
                          scale: scale,
                          child: glyph(widget.icon),
                        ),
                );
              case InteractionSuite.standard:
                return glyph(widget.icon);
            }
          },
        ),
      ),
    );
  }
}

class _SpotPainter extends CustomPainter {
  _SpotPainter(this.p, this.alpha);
  final InteractionPalette p;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width,
    );
    canvas.drawOval(
      r,
      Paint()
        ..shader = RadialGradient(colors: [p.light(alpha), p.light(0)])
            .createShader(r),
    );
  }

  @override
  bool shouldRepaint(_SpotPainter old) => old.alpha != alpha;
}

/// Icon button with two states (favourite, pin, show password…). Built on
/// [SuitePressable] so hover, press and focus follow the suite; the glyph
/// change uses [SuiteIconSwap]. The value is owned by the caller, so a
/// rejected change simply leaves the icon as it was.
class SuiteIconToggle extends StatefulWidget {
  const SuiteIconToggle({
    required this.value,
    required this.offIcon,
    required this.onIcon,
    required this.onChanged,
    required this.semanticLabel,
    this.onColor,
    super.key,
  });

  final bool value;
  final IconData offIcon;
  final IconData onIcon;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  /// Colour of the "on" glyph (e.g. a warning-gold star). Defaults to accent.
  final Color? onColor;

  @override
  State<SuiteIconToggle> createState() => _SuiteIconToggleState();
}

class _SuiteIconToggleState extends State<SuiteIconToggle> {
  bool _keyboard = false;

  @override
  Widget build(BuildContext context) {
    final p = InteractionScope.of(context).palette;
    final onChanged = widget.onChanged;
    // One node carrying role, name, state and the activation itself; the
    // pressable below is excluded so nothing is announced twice. Screen
    // reader activation takes the instant (non-decorative) path.
    return Semantics(
      button: true,
      toggled: widget.value,
      enabled: onChanged != null,
      label: widget.semanticLabel,
      onTap: onChanged == null
          ? null
          : () {
              _keyboard = true;
              onChanged(!widget.value);
            },
      excludeSemantics: true,
      child: SuitePressable(
        kind: PressableKind.icon,
        minHeight: 32,
        padding: const EdgeInsets.all(7),
        semanticLabel: widget.semanticLabel,
        onActivate: widget.onChanged == null
            ? null
            : (source) {
                _keyboard = source == InteractionSource.keyboard;
                widget.onChanged!(!widget.value);
              },
        builder: (context, v) => SuiteIconSwap(
          icon: widget.value ? widget.onIcon : widget.offIcon,
          instant: _keyboard,
          color: widget.value ? (widget.onColor ?? p.accent) : v.foreground,
        ),
      ),
    );
  }
}

/// Paints [paintBrackets] around a small box; shared by compact controls.
void paintSmallBrackets(Canvas canvas, Rect rect, Color color) =>
    paintBrackets(canvas, rect, color: color, length: 4, width: 1.5);
