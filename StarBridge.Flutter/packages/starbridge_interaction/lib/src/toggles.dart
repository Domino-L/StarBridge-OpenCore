import 'dart:math' as math;
import 'dart:ui' show PathMetric, lerpDouble;

import 'package:flutter/material.dart';

import 'effect_host.dart';
import 'painters.dart';
import 'suite.dart';

/// Shared focus, hover and keyboard handling for the two toggles.
mixin _ToggleBehaviour<T extends StatefulWidget> on State<T> {
  bool focused = false;
  bool hovered = false;
  InteractionSource pendingSource = InteractionSource.programmatic;

  bool get enabled;
  void request(InteractionSource source);

  Widget wrap(
    Widget child, {
    required String? label,
    required bool? checked,
    bool isSwitch = false,
    FocusNode? focusNode,
  }) {
    return Semantics(
      toggled: isSwitch ? checked : null,
      checked: isSwitch ? null : checked,
      mixed: !isSwitch && checked == null,
      enabled: enabled,
      label: label,
      child: FocusableActionDetector(
        focusNode: focusNode,
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              request(InteractionSource.keyboard);
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => request(InteractionSource.pointer) : null,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// On/off switch. The value is owned by the caller: when an async change is
/// rejected the caller keeps the old value and the switch simply stays.
///
/// Rail: the knob stretches toward the new side, then settles; the track
/// fills along the travel direction. Scan: the knob locks instantly, a beam
/// crosses the track and brackets close in. Glow: the knob slides, lights
/// up and drops one ring.
///
/// Server-confirmed settings: pass the requested value as [pendingValue]
/// while waiting. The knob goes to the requested side at once (the press
/// gets its normal feedback) but is drawn hollow, and the switch takes no
/// further input until the caller clears [pendingValue]. Confirmed: set
/// [value] to it, nothing more plays. Refused: keep [value]; the knob
/// returns without decoration and [error] can keep a static danger edge
/// until the next change. While waiting, rail runs a short shuttle inside
/// the track, scan a slow line across it, glow a breathing knob light,
/// standard a small arc; reduced motion keeps only the hollow knob.
class SuiteSwitch extends StatefulWidget {
  const SuiteSwitch({
    required this.value,
    required this.onChanged,
    this.pendingValue,
    this.error = false,
    this.semanticLabel,
    this.focusNode,
    this.changeSource,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// The value requested and not yet confirmed; null when settled.
  final bool? pendingValue;

  /// The last request failed: a static danger edge.
  final bool error;
  final String? semanticLabel;
  final FocusNode? focusNode;

  /// Optional external activation origin for an accessible host control.
  final InteractionSource? changeSource;

  @override
  State<SuiteSwitch> createState() => _SuiteSwitchState();
}

class _SuiteSwitchState extends State<SuiteSwitch>
    with TickerProviderStateMixin, _ToggleBehaviour<SuiteSwitch> {
  late final _t = AnimationController(vsync: this, value: _target ? 1 : 0);
  final _fx = GlobalKey<EffectHostState>();

  /// Waiting loop, only while pending and motion is allowed.
  late final _wait = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Where the knob should be: the request while pending, else the value.
  bool get _target => widget.pendingValue ?? widget.value;
  bool get _pending => widget.pendingValue != null;

  void _syncWait() {
    final run = _pending && InteractionScope.of(context).animates;
    if (run && !_wait.isAnimating) {
      _wait.repeat();
    } else if (!run && _wait.isAnimating) {
      _wait
        ..stop()
        ..value = 0;
    }
  }

  /// Travel progress for the rail stretch (separate from the position so the
  /// stretch can be computed from both edges).
  double _from = 0;

  @override
  // Stays enabled (and focused) while pending; [request] ignores input.
  bool get enabled => widget.onChanged != null;

  @override
  void request(InteractionSource source) {
    if (_pending) return;
    pendingSource = source;
    widget.onChanged?.call(!widget.value);
  }

  @override
  void didUpdateWidget(SuiteSwitch old) {
    super.didUpdateWidget(old);
    _syncWait();
    if (widget.changeSource == InteractionSource.keyboard) {
      _t.value = _target ? 1 : 0;
      _fx.currentState?.clear();
    }
    if (_target == (old.pendingValue ?? old.value)) return;
    final data = InteractionScope.of(context);
    final target = _target ? 1.0 : 0.0;
    final keyboard =
        widget.changeSource == InteractionSource.keyboard ||
        pendingSource == InteractionSource.keyboard;
    // Decorations belong to the control the user actually pressed; changes
    // driven from elsewhere (select all, sync) only move the knob.
    final pointer =
        !keyboard &&
        (widget.changeSource == InteractionSource.pointer ||
            pendingSource == InteractionSource.pointer);
    pendingSource = InteractionSource.programmatic;
    final instant =
        !data.animates || keyboard || data.suite == InteractionSuite.scan;
    _from = _t.value;
    if (instant) {
      _t.value = target;
    } else {
      _t.duration = data.motion.select;
      _t.animateTo(target, curve: Curves.linear);
    }
    if (!data.animates || !pointer) {
      _fx.currentState?.clear();
      return;
    }
    switch (data.suite) {
      case InteractionSuite.scan:
        _fx.currentState
          ?..play(TransientEffect.beam)
          ..play(TransientEffect.bracketFlash);
      case InteractionSuite.glow:
        _fx.currentState?.play(
          TransientEffect.ring,
          at: Offset(_target ? 29 : 11, 11),
        );
      case InteractionSuite.standard || InteractionSuite.rail:
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) {
      _t.value = _target ? 1 : 0;
    }
    _syncWait();
  }

  @override
  void dispose() {
    _t.dispose();
    _wait.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final label = widget.semanticLabel ?? '';
    return wrap(
      label: _pending
          ? '$label，正在确认'
          : widget.error
          ? '$label，未能更改'
          : widget.semanticLabel,
      checked: widget.value,
      isSwitch: true,
      focusNode: widget.focusNode,
      EffectHost(
        key: _fx,
        borderRadius: suiteRadius(data.suite, 11),
        bracketInset: -4,
        bracketLength: 5,
        child: SizedBox(
          width: 40,
          height: 22,
          child: CustomPaint(painter: _SwitchPainter(this, data, _t, _wait)),
        ),
      ),
    );
  }
}

class _SwitchPainter extends CustomPainter {
  _SwitchPainter(this.s, this.data, Animation<double> t, this.wait)
    : t = t,
      super(repaint: Listenable.merge([t, wait]));

  final _SuiteSwitchState s;
  final InteractionData data;
  final Animation<double> t;
  final Animation<double> wait;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final v = t.value;
    final on = s._target;
    final suite = data.suite;
    final pending = s._pending;
    // Pending reads as "on its way", not disabled: keep the accent.
    final enabled = s.enabled || pending;
    final rect = Offset.zero & size;
    final radius = suiteRadius(suite, 11);
    final rrect = radius.toRRect(rect);
    final offFill = p.raised;
    final onFill = enabled ? p.accent : p.textDisabled;

    if (suite == InteractionSuite.rail) {
      canvas.drawRRect(rrect, Paint()..color = offFill);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * v, size.height),
        Paint()..color = onFill,
      );
      canvas.restore();
    } else {
      canvas.drawRRect(rrect, Paint()..color = Color.lerp(offFill, onFill, v)!);
    }
    final failed = s.widget.error && !pending;
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = failed ? 1.5 : 1
        ..color = failed ? p.danger : Color.lerp(p.border, onFill, v)!,
    );
    if (pending && wait.value > 0) _paintWaiting(canvas, size, rrect, p);
    if (suite == InteractionSuite.glow && on && enabled && !pending) {
      paintGlowStrokes(canvas, rrect, p.accent, p.isDark ? 0.7 * v : 0.4 * v);
    }

    // Knob: 16×16, travelling between x = 3 and x = 21.
    const start = 3.0, end = 21.0, knob = 16.0;
    double left = lerpDouble(start, end, v)!;
    double right = left + knob;
    final moving =
        t is AnimationController &&
        (t as AnimationController).isAnimating &&
        suite == InteractionSuite.rail;
    if (moving) {
      final goingOn = on;
      final from = s._from;
      final total = (goingOn ? 1 - from : from).abs();
      final progress = total == 0
          ? 1.0
          : ((v - from).abs() / total).clamp(0.0, 1.0);
      final lead = (progress / 0.45).clamp(0.0, 1.0);
      final trail = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
      final fromLeft = lerpDouble(start, end, from)!;
      final toLeft = goingOn ? end : start;
      if (goingOn) {
        right = lerpDouble(
          fromLeft + knob,
          toLeft + knob,
          SuiteMotion.curve.transform(lead),
        )!;
        left = lerpDouble(
          fromLeft,
          toLeft,
          SuiteMotion.curve.transform(trail),
        )!;
      } else {
        left = lerpDouble(fromLeft, toLeft, SuiteMotion.curve.transform(lead))!;
        right = lerpDouble(
          fromLeft + knob,
          toLeft + knob,
          SuiteMotion.curve.transform(trail),
        )!;
      }
    }
    final knobRect = Rect.fromLTRB(left, 3, right, 3 + knob);
    final knobColor = Color.lerp(
      enabled ? p.textSecondary : p.textDisabled,
      p.isDark ? Colors.white : p.onAccent,
      v,
    )!;
    final knobRRect = suite == InteractionSuite.scan
        ? RRect.fromRectXY(knobRect, 1.5, 1.5)
        : RRect.fromRectXY(knobRect, knob / 2, knob / 2);
    if (suite == InteractionSuite.glow && on && enabled && p.isDark) {
      final breathe = pending
          ? 0.25 + 0.35 * (0.5 - 0.5 * math.cos(wait.value * 2 * math.pi))
          : 0.6;
      paintGlowStrokes(canvas, knobRRect, Colors.white, breathe * v);
    }
    if (pending) {
      // Hollow knob: the static "waiting for confirmation" mark.
      canvas.drawRRect(
        knobRRect.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = knobColor,
      );
      if (suite == InteractionSuite.standard && wait.value > 0) {
        canvas.drawArc(
          knobRect.deflate(4),
          wait.value * 2 * math.pi,
          math.pi * 0.9,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = knobColor,
        );
      }
    } else {
      canvas.drawRRect(knobRRect, Paint()..color = knobColor);
    }

    if (s.focused) {
      canvas.drawRRect(
        rrect.inflate(2.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
  }

  void _paintWaiting(
    Canvas canvas,
    Size size,
    RRect rrect,
    InteractionPalette p,
  ) {
    final w = wait.value;
    canvas.save();
    canvas.clipRRect(rrect);
    switch (data.suite) {
      case InteractionSuite.rail:
        // A short lit segment shuttling along the track.
        final x = (0.5 - 0.5 * math.cos(w * 2 * math.pi)) * (size.width - 10);
        canvas.drawRect(
          Rect.fromLTWH(x, size.height - 3, 10, 2),
          Paint()..color = p.onAccent.withValues(alpha: 0.85),
        );
      case InteractionSuite.scan:
        canvas.drawRect(
          Rect.fromLTWH(w * size.width - 1, 0, 1.5, size.height),
          Paint()..color = p.onAccent.withValues(alpha: 0.7),
        );
      case InteractionSuite.glow || InteractionSuite.standard:
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwitchPainter old) => true;
}

/// Checkbox with optional mixed state (`value == null`).
///
/// Standard: a 160 ms, 6 % confirm pop (QualityPass ⑤). Rail: the tick is
/// drawn along its path. Scan: the tick locks in with a short flicker and
/// brackets close in. Glow: the tick pops and one ring spreads. Unchecking
/// is always immediate.
class SuiteCheckbox extends StatefulWidget {
  const SuiteCheckbox({
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.semanticLabel,
    this.focusNode,
    this.changeSource,
    super.key,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final String? semanticLabel;
  final FocusNode? focusNode;
  /// Origin supplied by a host row; programmatic updates do not draw a tick.
  final InteractionSource? changeSource;

  @override
  State<SuiteCheckbox> createState() => _SuiteCheckboxState();
}

class _SuiteCheckboxState extends State<SuiteCheckbox>
    with SingleTickerProviderStateMixin, _ToggleBehaviour<SuiteCheckbox> {
  late final _t = AnimationController(vsync: this, value: 1);
  final _fx = GlobalKey<EffectHostState>();

  @override
  bool get enabled => widget.onChanged != null;

  @override
  void request(InteractionSource source) {
    pendingSource = source;
    final next = switch (widget.value) {
      false => true,
      true => widget.tristate ? null : false,
      null => false,
    };
    widget.onChanged?.call(next);
  }

  @override
  void didUpdateWidget(SuiteCheckbox old) {
    super.didUpdateWidget(old);
    final keyboard =
        widget.changeSource == InteractionSource.keyboard ||
        pendingSource == InteractionSource.keyboard;
    if (keyboard) {
      _t.value = 1;
      _fx.currentState?.clear();
    }
    if (widget.value == old.value) return;
    final data = InteractionScope.of(context);
    final animate =
        data.animates &&
        // Only a click on this box animates its tick; select-all and other
        // external changes set it at once, all boxes in the same frame.
        !keyboard &&
        (widget.changeSource == InteractionSource.pointer ||
            pendingSource == InteractionSource.pointer) &&
        widget.value == true;
    pendingSource = InteractionSource.programmatic;
    if (!animate) {
      _t.value = 1;
      _fx.currentState?.clear();
      return;
    }
    _t.duration = switch (data.suite) {
      InteractionSuite.scan => const Duration(milliseconds: 320),
      InteractionSuite.standard => const Duration(milliseconds: 160),
      _ => data.motion.select,
    };
    _t.forward(from: 0);
    if (data.suite == InteractionSuite.scan) {
      _fx.currentState?.play(TransientEffect.bracketFlash);
    } else if (data.suite == InteractionSuite.glow) {
      _fx.currentState?.play(TransientEffect.ring, at: const Offset(9, 9));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) _t.value = 1;
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    return wrap(
      label: widget.semanticLabel,
      checked: widget.value,
      focusNode: widget.focusNode,
      EffectHost(
        key: _fx,
        borderRadius: suiteRadius(data.suite, 4),
        bracketInset: -5,
        bracketLength: 5,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CustomPaint(painter: _CheckPainter(this, data, _t)),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.s, this.data, this.t) : super(repaint: t);

  final _SuiteCheckboxState s;
  final InteractionData data;
  final Animation<double> t;

  static const _flicker = [0.0, 1.0, 0.2, 1.0, 0.5, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final value = s.widget.value;
    final suite = data.suite;
    final enabled = s.enabled;
    final rect = Offset.zero & size;
    final rrect = suiteRadius(suite, 4).toRRect(rect);
    final marked = value != false;
    final fill = enabled ? p.accent : p.textDisabled;
    final v = t.value;

    if (marked) {
      canvas.drawRRect(rrect, Paint()..color = fill);
      if (suite == InteractionSuite.glow && enabled) {
        paintGlowStrokes(canvas, rrect, p.accent, p.isDark ? 0.8 : 0.4);
      }
    } else {
      canvas.drawRRect(
        rrect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = enabled
              ? Color.lerp(p.textSecondary, p.edge(), s.hovered ? 0.6 : 0)!
              : p.textDisabled,
      );
    }

    if (marked) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = p.onAccent;
      if (value == null) {
        canvas.drawLine(const Offset(5, 9), const Offset(13, 9), stroke);
      } else {
        final path = Path()
          ..moveTo(4.5, 9.5)
          ..lineTo(7.8, 12.6)
          ..lineTo(13.5, 5.8);
        switch (suite) {
          case InteractionSuite.rail:
            final metrics = path.computeMetrics().toList();
            final total = metrics.fold<double>(
              0,
              (a, PathMetric m) => a + m.length,
            );
            var remaining = total * SuiteMotion.curve.transform(v);
            for (final m in metrics) {
              final len = math.min(remaining, m.length);
              canvas.drawPath(m.extractPath(0, len), stroke);
              remaining -= len;
            }
          case InteractionSuite.scan:
            final step = (v * (_flicker.length - 1)).floor().clamp(
              0,
              _flicker.length - 1,
            );
            stroke.color = p.onAccent.withValues(
              alpha: v >= 1 ? 1 : _flicker[step],
            );
            canvas.drawPath(path, stroke);
          case InteractionSuite.glow:
            final scale = v < 0.6
                ? lerpDouble(0.4, 1.18, v / 0.6)!
                : lerpDouble(1.18, 1, (v - 0.6) / 0.4)!;
            canvas.save();
            canvas.translate(9, 9);
            canvas.scale(scale);
            canvas.translate(-9, -9);
            canvas.drawPath(path, stroke);
            canvas.restore();
          case InteractionSuite.standard:
            // Confirm pop: up 6 % and back, no bounce past rest.
            final pop = v < 0.5
                ? lerpDouble(1, 1.06, v / 0.5)!
                : lerpDouble(1.06, 1, (v - 0.5) / 0.5)!;
            canvas.save();
            canvas.translate(9, 9);
            canvas.scale(pop);
            canvas.translate(-9, -9);
            canvas.drawPath(path, stroke);
            canvas.restore();
        }
      }
    }

    if (s.focused) {
      canvas.drawRRect(
        rrect.inflate(2.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => true;
}
