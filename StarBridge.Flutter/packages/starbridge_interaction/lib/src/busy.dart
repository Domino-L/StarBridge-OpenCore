import 'dart:math' as math;
import 'dart:ui' show PathMetric, lerpDouble;

import 'package:flutter/material.dart';

import 'effect_host.dart';
import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

/// Outcome of a finished task, used to pick the completion flash.
enum TaskOutcome { success, failure }

/// Wraps a panel whose content is being refreshed. The content always stays
/// visible and interactive; only a local marker shows the wait.
///
/// Busy: rail runs a shuttle along the top edge; scan passes a looping line
/// with a light veil; glow keeps a quiet static edge light (the label's
/// spinner carries the motion). Standard relies on the label spinner.
/// When [doneToken] changes, a completion flash plays in [doneOutcome]'s
/// tone. Reduced motion shows no loop at all; use [SuiteBusyLabel] text.
class SuiteBusyFrame extends StatefulWidget {
  const SuiteBusyFrame({
    required this.busy,
    required this.child,
    this.doneToken,
    this.doneOutcome = TaskOutcome.success,
    this.radius = 9,
    super.key,
  });

  final bool busy;
  final Widget child;
  final Object? doneToken;
  final TaskOutcome doneOutcome;
  final double radius;

  @override
  State<SuiteBusyFrame> createState() => _SuiteBusyFrameState();
}

class _SuiteBusyFrameState extends State<SuiteBusyFrame>
    with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(vsync: this);
  final _fx = GlobalKey<EffectHostState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(SuiteBusyFrame old) {
    super.didUpdateWidget(old);
    _syncLoop();
    if (widget.doneToken != old.doneToken && old.doneToken != null) _flash();
  }

  void _syncLoop() {
    final data = InteractionScope.of(context);
    final loops =
        widget.busy &&
        data.animates &&
        (data.suite == InteractionSuite.rail ||
            data.suite == InteractionSuite.scan);
    if (loops && !_loop.isAnimating) {
      _loop.duration = Duration(
        milliseconds: data.suite == InteractionSuite.rail ? 1000 : 900,
      );
      _loop.repeat();
    } else if (!loops && _loop.isAnimating) {
      _loop.reset();
    }
  }

  void _flash() {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final tone = widget.doneOutcome == TaskOutcome.success ? null : p.danger;
    final fx = _fx.currentState;
    switch (data.suite) {
      case InteractionSuite.rail:
        fx?.play(TransientEffect.sweep, color: tone);
      case InteractionSuite.scan:
        fx?.play(TransientEffect.bracketFlash, color: tone);
        if (tone == null) fx?.play(TransientEffect.scanLine);
      case InteractionSuite.glow:
        fx?.play(TransientEffect.pulse, color: tone);
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final radius = suiteRadius(data.suite, widget.radius);
    return EffectHost(
      key: _fx,
      borderRadius: radius,
      child: CustomPaint(
        foregroundPainter: _BusyPainter(this, data, radius, _loop),
        child: widget.child,
      ),
    );
  }
}

class _BusyPainter extends CustomPainter {
  _BusyPainter(this.s, this.data, this.radius, this.loop)
    : super(repaint: loop);

  final _SuiteBusyFrameState s;
  final InteractionData data;
  final BorderRadius radius;
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    if (!s.widget.busy || !data.animates) return;
    final p = data.palette;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.save();
        canvas.clipRRect(rrect);
        final w = size.width * 0.4;
        final x =
            -w + (size.width + w) * SuiteMotion.curve.transform(loop.value);
        final seg = Rect.fromLTWH(x, 0, w, 2);
        canvas.drawRect(
          seg,
          Paint()
            ..shader = LinearGradient(colors: [p.edge(0), p.edge(), p.edge(0)])
                .createShader(seg),
        );
        canvas.restore();
      case InteractionSuite.scan:
        canvas.save();
        canvas.clipRRect(rrect);
        canvas.drawRRect(
          rrect,
          Paint()..color = p.surface.withValues(alpha: 0.28),
        );
        paintScanLine(
          canvas,
          rect,
          loop.value.clamp(0.001, 0.999),
          p.edge(0.8),
        );
        canvas.restore();
      case InteractionSuite.glow:
        canvas.drawRRect(
          rrect.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = p.edge(0.45),
        );
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_BusyPainter old) => true;
}

/// "What is happening" text for a wait. Standard shows a Material spinner,
/// glow a small lit arc, rail and scan text only (their frame carries the
/// motion). Reduced motion always shows a static icon with the text.
class SuiteBusyLabel extends StatelessWidget {
  const SuiteBusyLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: p.textSecondary);
    Widget? lead;
    if (!data.animates) {
      lead = Icon(Icons.hourglass_empty, size: 14, color: p.textSecondary);
    } else if (data.suite == InteractionSuite.standard) {
      lead = SizedBox.square(
        dimension: 13,
        child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
      );
    } else if (data.suite == InteractionSuite.glow) {
      lead = const _GlowSpinner();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lead != null) ...[lead, const SizedBox(width: 6)],
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}

class _GlowSpinner extends StatefulWidget {
  const _GlowSpinner();

  @override
  State<_GlowSpinner> createState() => _GlowSpinnerState();
}

class _GlowSpinnerState extends State<_GlowSpinner>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = InteractionScope.of(context).palette;
    return SizedBox.square(
      dimension: 14,
      child: CustomPaint(painter: _ArcPainter(_c, p)),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.t, this.p) : super(repaint: t);
  final Animation<double> t;
  final InteractionPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final start = t.value * math.pi * 2;
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = p.light(0.18),
    );
    if (p.isDark) {
      canvas.drawArc(
        rect.inflate(1.5),
        start,
        1.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = p.edge(0.25),
      );
    }
    canvas.drawArc(
      rect,
      start,
      1.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = p.edge(),
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => true;
}

enum ActionPhase { idle, busy, success, failure }

/// A submit button whose look follows the real task [phase]. Success only
/// appears once the caller reports it; failure keeps the button usable for
/// retry and shows a static danger mark. While busy the button ignores
/// input and says so to assistive technology.
///
/// Success: rail wipes green along the button and draws the tick; scan
/// closes brackets onto the button and the tick locks in; glow fills green,
/// pops the tick and drops one ring. Standard just swaps the label.
class SuiteActionButton extends StatefulWidget {
  const SuiteActionButton({
    required this.phase,
    required this.onPressed,
    required this.label,
    required this.busyLabel,
    required this.successLabel,
    required this.failureLabel,
    this.minWidth = 120,
    super.key,
  });

  final ActionPhase phase;
  final VoidCallback onPressed;
  final String label;
  final String busyLabel;
  final String successLabel;
  final String failureLabel;
  final double minWidth;

  @override
  State<SuiteActionButton> createState() => _SuiteActionButtonState();
}

class _SuiteActionButtonState extends State<SuiteActionButton>
    with TickerProviderStateMixin {
  late final _done = AnimationController(vsync: this, value: 1);
  late final _loop = AnimationController(vsync: this);
  final _fx = GlobalKey<EffectHostState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(null);
  }

  @override
  void didUpdateWidget(SuiteActionButton old) {
    super.didUpdateWidget(old);
    _sync(old.phase);
  }

  void _sync(ActionPhase? old) {
    final data = InteractionScope.of(context);
    final busyLoop =
        widget.phase == ActionPhase.busy &&
        data.animates &&
        (data.suite == InteractionSuite.rail ||
            data.suite == InteractionSuite.scan);
    if (busyLoop && !_loop.isAnimating) {
      _loop
        ..duration = const Duration(milliseconds: 1000)
        ..repeat();
    } else if (!busyLoop) {
      _loop.reset();
    }
    if (!data.animates) {
      _done.value = 1;
      return;
    }
    if (old == null || old == widget.phase) return;
    if (widget.phase == ActionPhase.success) {
      _done
        ..duration = data.suite == InteractionSuite.scan
            ? const Duration(milliseconds: 320)
            : data.motion.select + const Duration(milliseconds: 120)
        ..forward(from: 0);
      final p = data.palette;
      switch (data.suite) {
        case InteractionSuite.scan:
          _fx.currentState?.play(
            TransientEffect.bracketFlash,
            color: p.success,
          );
        case InteractionSuite.glow:
          final box = context.findRenderObject() as RenderBox?;
          final w = box?.size.width ?? 120;
          _fx.currentState?.play(
            TransientEffect.ring,
            color: p.success,
            ringScale: w / 14,
          );
        case InteractionSuite.standard || InteractionSuite.rail:
          break;
      }
    } else if (widget.phase == ActionPhase.failure &&
        data.suite == InteractionSuite.scan) {
      _fx.currentState?.play(
        TransientEffect.bracketFlash,
        color: data.palette.danger,
      );
    }
  }

  @override
  void dispose() {
    _done.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final phase = widget.phase;
    final busy = phase == ActionPhase.busy;
    final label = switch (phase) {
      ActionPhase.idle => widget.label,
      ActionPhase.busy => widget.busyLabel,
      ActionPhase.success => widget.successLabel,
      ActionPhase.failure => widget.failureLabel,
    };
    final radius = suiteRadius(data.suite, 6);
    // One semantics node: a button with the current label and a tap action
    // (none while busy). liveRegion announces label changes (saving, saved,
    // failed) on this same node, so the status is never read twice. The
    // inner pressable's own node is replaced, not added.
    return Semantics(
      container: true,
      button: true,
      enabled: !busy,
      liveRegion: true,
      label: label,
      onTap: busy ? null : widget.onPressed,
      excludeSemantics: true,
      child: AbsorbPointer(
        absorbing: busy,
        child: EffectHost(
          key: _fx,
          borderRadius: radius,
          bracketInset: -3,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: widget.minWidth),
            child: SuitePressable(
              kind: PressableKind.primary,
              minHeight: 34,
              onPressed: () {
                if (widget.phase != ActionPhase.busy) widget.onPressed();
              },
              builder: (context, v) {
                final fg = phase == ActionPhase.success
                    ? p.onSuccess
                    : v.foreground;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ActionFacePainter(
                          phase: phase,
                          data: data,
                          radius: radius,
                          done: _done,
                          loop: _loop,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (busy &&
                              data.animates &&
                              data.suite == InteractionSuite.standard) ...[
                            SizedBox.square(
                              dimension: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: fg,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (phase == ActionPhase.success) ...[
                            SizedBox.square(
                              dimension: 15,
                              child: CustomPaint(
                                painter: _TickPainter(_done, data, fg),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (phase == ActionPhase.failure) ...[
                            Icon(Icons.refresh, size: 15, color: fg),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionFacePainter extends CustomPainter {
  _ActionFacePainter({
    required this.phase,
    required this.data,
    required this.radius,
    required this.done,
    required this.loop,
  }) : super(repaint: Listenable.merge([done, loop]));

  final ActionPhase phase;
  final InteractionData data;
  final BorderRadius radius;
  final Animation<double> done;
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    canvas.save();
    canvas.clipRRect(rrect);
    switch (phase) {
      case ActionPhase.success:
        final d = SuiteMotion.curve.transform(done.value);
        final w = data.suite == InteractionSuite.rail
            ? size.width * d
            : size.width;
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, size.height),
          Paint()..color = p.success,
        );
      case ActionPhase.busy:
        if (data.animates && data.suite == InteractionSuite.rail) {
          final w = size.width * 0.4;
          final x =
              -w + (size.width + w) * SuiteMotion.curve.transform(loop.value);
          final seg = Rect.fromLTWH(x, size.height - 2, w, 2);
          canvas.drawRect(
            seg,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  p.onAccent.withValues(alpha: 0),
                  p.onAccent,
                  p.onAccent.withValues(alpha: 0),
                ],
              ).createShader(seg),
          );
        } else if (data.animates && data.suite == InteractionSuite.scan) {
          paintScanLine(
            canvas,
            rect,
            loop.value.clamp(0.001, 0.999),
            p.onAccent.withValues(alpha: 0.7),
          );
        }
      case ActionPhase.failure:
        switch (data.suite) {
          case InteractionSuite.rail:
            paintEdgeLine(canvas, rect, p.danger, height: 3);
          case InteractionSuite.scan:
            break;
          case InteractionSuite.glow || InteractionSuite.standard:
            break;
        }
      case ActionPhase.idle:
        break;
    }
    canvas.restore();
    if (phase == ActionPhase.failure) {
      if (data.suite == InteractionSuite.scan) {
        paintBrackets(canvas, rect.deflate(2), color: p.danger);
      } else if (data.suite == InteractionSuite.glow) {
        paintGlowStrokes(canvas, rrect, p.danger, 0.6);
      }
    }
    if (phase == ActionPhase.busy &&
        data.suite == InteractionSuite.glow &&
        data.animates) {
      paintGlowStrokes(canvas, rrect, p.accent, 0.35);
    }
    if (phase == ActionPhase.success && data.suite == InteractionSuite.glow) {
      paintGlowStrokes(canvas, rrect, p.success, p.isDark ? 0.8 : 0.45);
    }
  }

  @override
  bool shouldRepaint(_ActionFacePainter old) => true;
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.t, this.data, this.color) : super(repaint: t);
  final Animation<double> t;
  final InteractionData data;
  final Color color;

  static const _flicker = [0.0, 1.0, 0.2, 1.0, 0.5, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final path = Path()
      ..moveTo(3 * s, 8.5 * s)
      ..lineTo(6.4 * s, 11.6 * s)
      ..lineTo(13 * s, 4.6 * s);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final v = t.value;
    switch (data.suite) {
      case InteractionSuite.rail:
        final drawT = ((v - 0.35) / 0.65).clamp(0.0, 1.0);
        final metrics = path.computeMetrics().toList();
        final total = metrics.fold<double>(
          0,
          (a, PathMetric m) => a + m.length,
        );
        var remaining = total * SuiteMotion.curve.transform(drawT);
        for (final m in metrics) {
          final len = math.min(remaining, m.length);
          if (len > 0) canvas.drawPath(m.extractPath(0, len), paint);
          remaining -= len;
        }
      case InteractionSuite.scan:
        final step = (v * (_flicker.length - 1)).floor().clamp(
          0,
          _flicker.length - 1,
        );
        paint.color = color.withValues(alpha: v >= 1 ? 1 : _flicker[step]);
        canvas.drawPath(path, paint);
      case InteractionSuite.glow:
        final scale = v < 0.6
            ? lerpDouble(0.4, 1.18, v / 0.6)!
            : lerpDouble(1.18, 1, (v - 0.6) / 0.4)!;
        canvas.save();
        canvas.translate(size.width / 2, size.height / 2);
        canvas.scale(scale);
        canvas.translate(-size.width / 2, -size.height / 2);
        canvas.drawPath(path, paint);
        canvas.restore();
      case InteractionSuite.standard:
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => true;
}
