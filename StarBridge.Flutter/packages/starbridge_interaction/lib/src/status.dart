import 'package:flutter/material.dart';

import 'busy.dart';
import 'effect_host.dart';
import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

// ---------------------------------------------------------------------------
// 25 · first load
// ---------------------------------------------------------------------------

/// Placeholder for content that has never loaded. Keeps the final layout's
/// structure (so nothing jumps when data arrives), says what is being read,
/// and never shows a fake percentage. The wait marker is local: rail runs a
/// line along the top, scan passes one line over the blocks, glow shows a
/// quiet arc next to the label, standard a spinner. Reduced motion: static
/// blocks with the text only.
class SuiteSkeleton extends StatelessWidget {
  const SuiteSkeleton({
    required this.label,
    this.lines = 3,
    this.height = 120,
    super.key,
  });

  final String label;
  final int lines;
  final double height;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    Widget block(double widthFactor, double h) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: suiteRadius(data.suite, 4),
        ),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: label,
      child: SuiteBusyFrame(
        busy: true,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                ExcludeSemantics(child: SuiteBusyLabel(label)),
                block(0.45, 14),
                for (var i = 0; i < lines; i++) block(i.isEven ? 0.9 : 0.7, 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 28 · progress
// ---------------------------------------------------------------------------

enum ProgressPhase { running, done, failed, cancelled }

/// Download / upload / import / update progress. [value] is the real
/// fraction (0–1) or null when the total is unknown (indeterminate). The bar
/// eases toward each new real value over a short time and never runs ahead.
///
/// Rail: a fill with a lit leading edge; indeterminate is a shuttle.
/// Scan: ten segments that light as they fill; indeterminate is one passing
/// scan block. Glow: a fill with a soft endpoint light; indeterminate is a
/// travelling soft light. Done: one short confirmation (rail turns success,
/// scan brackets lock, glow pulses once). Failed / cancelled: static marks,
/// no celebration.
class SuiteProgressBar extends StatefulWidget {
  const SuiteProgressBar({
    required this.value,
    required this.phase,
    this.semanticLabel,
    super.key,
  });

  final double? value;
  final ProgressPhase phase;
  final String? semanticLabel;

  @override
  State<SuiteProgressBar> createState() => _SuiteProgressBarState();
}

class _SuiteProgressBarState extends State<SuiteProgressBar>
    with TickerProviderStateMixin {
  late final _shown = AnimationController(
    vsync: this,
    value: widget.value ?? 0,
  );
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  final _fx = GlobalKey<EffectHostState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(null);
  }

  @override
  void didUpdateWidget(SuiteProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(oldWidget);
  }

  void _sync(SuiteProgressBar? old) {
    final data = InteractionScope.of(context);
    final v = widget.value;
    if (v != null && v != _shown.value) {
      if (!data.animates || v < _shown.value) {
        _shown.value = v; // never animate backwards (resets, corrections)
      } else {
        _shown.animateTo(
          v,
          duration: const Duration(milliseconds: 220),
          curve: SuiteMotion.curve,
        );
      }
    }
    final looping =
        v == null && widget.phase == ProgressPhase.running && data.animates;
    if (looping && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!looping && _loop.isAnimating) {
      _loop.reset();
    }
    if (old != null &&
        old.phase != widget.phase &&
        widget.phase == ProgressPhase.done &&
        data.animates) {
      final p = data.palette;
      switch (data.suite) {
        case InteractionSuite.scan:
          _fx.currentState?.play(
            TransientEffect.bracketFlash,
            color: p.success,
            duration: const Duration(milliseconds: 420),
          );
        case InteractionSuite.glow:
          _fx.currentState?.play(TransientEffect.pulse, color: p.success);
        case InteractionSuite.rail:
          _fx.currentState?.play(TransientEffect.sweep, color: p.success);
        case InteractionSuite.standard:
          break;
      }
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final v = widget.value;
    return Semantics(
      label: widget.semanticLabel,
      value: v == null ? '进行中' : '${(v * 100).round()}%',
      child: EffectHost(
        key: _fx,
        borderRadius: suiteRadius(data.suite, 3),
        bracketInset: -3,
        bracketLength: 5,
        child: SizedBox(
          height: 8,
          child: CustomPaint(
            painter: _ProgressPainter(
              data: data,
              shown: _shown,
              loop: _loop,
              indeterminate: v == null,
              phase: widget.phase,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.data,
    required this.shown,
    required this.loop,
    required this.indeterminate,
    required this.phase,
  }) : super(repaint: Listenable.merge([shown, loop]));

  final InteractionData data;
  final Animation<double> shown;
  final Animation<double> loop;
  final bool indeterminate;
  final ProgressPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final suite = data.suite;
    final track = Rect.fromLTWH(0, (size.height - 4) / 2, size.width, 4);
    final r = suite == InteractionSuite.scan ? 0.0 : 2.0;
    final color = switch (phase) {
      ProgressPhase.done => p.success,
      ProgressPhase.failed => p.danger,
      ProgressPhase.cancelled => p.textDisabled,
      ProgressPhase.running => p.accent,
    };
    canvas.drawRRect(RRect.fromRectXY(track, r, r), Paint()..color = p.raised);

    if (indeterminate && phase == ProgressPhase.running) {
      if (!data.animates) {
        // Static "in progress" pattern: dashes, no motion.
        for (var x = 0.0; x < size.width; x += 12) {
          canvas.drawRect(
            Rect.fromLTWH(x, track.top, 6, track.height),
            Paint()..color = color.withValues(alpha: 0.5),
          );
        }
        return;
      }
      final t = loop.value;
      canvas.save();
      canvas.clipRRect(RRect.fromRectXY(track, r, r));
      switch (suite) {
        case InteractionSuite.scan:
          final w = size.width * 0.18;
          final x = -w + (size.width + w) * t;
          canvas.drawRect(
            Rect.fromLTWH(x, track.top, w, track.height),
            Paint()..color = color,
          );
        case InteractionSuite.glow:
          final c = Offset(size.width * t, track.center.dy);
          final g = Rect.fromCircle(center: c, radius: size.width * 0.18);
          canvas.drawOval(
            g,
            Paint()
              ..shader = RadialGradient(
                colors: [color, color.withValues(alpha: 0)],
              ).createShader(g),
          );
        case InteractionSuite.rail || InteractionSuite.standard:
          final w = size.width * 0.35;
          final x = -w + (size.width + w) * SuiteMotion.curve.transform(t);
          final seg = Rect.fromLTWH(x, track.top, w, track.height);
          canvas.drawRect(
            seg,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  color.withValues(alpha: 0),
                  color,
                  color.withValues(alpha: 0),
                ],
              ).createShader(seg),
          );
      }
      canvas.restore();
      return;
    }

    final v = shown.value.clamp(0.0, 1.0);
    final fill = Rect.fromLTWH(0, track.top, size.width * v, track.height);
    switch (suite) {
      case InteractionSuite.scan:
        const n = 10;
        final segW = (size.width - (n - 1) * 2) / n;
        for (var i = 0; i < n; i++) {
          final x = i * (segW + 2);
          final part = ((v * n) - i).clamp(0.0, 1.0);
          canvas.drawRect(
            Rect.fromLTWH(x, track.top, segW, track.height),
            Paint()..color = p.border.withValues(alpha: 0.35),
          );
          if (part > 0) {
            canvas.drawRect(
              Rect.fromLTWH(x, track.top, segW * part, track.height),
              Paint()..color = color,
            );
          }
        }
      case InteractionSuite.rail:
        canvas.drawRRect(RRect.fromRectXY(fill, r, r), Paint()..color = color);
        if (phase == ProgressPhase.running && v > 0) {
          canvas.drawRect(
            Rect.fromLTWH(fill.right - 2, track.top - 2, 2, track.height + 4),
            Paint()..color = p.edge(),
          );
        }
      case InteractionSuite.glow:
        canvas.drawRRect(RRect.fromRectXY(fill, r, r), Paint()..color = color);
        if (phase == ProgressPhase.running && v > 0) {
          final g = Rect.fromCircle(
            center: Offset(fill.right, track.center.dy),
            radius: 9,
          );
          canvas.drawOval(
            g,
            Paint()
              ..shader = RadialGradient(colors: [p.light(0.6), p.light(0)])
                  .createShader(g),
          );
        }
      case InteractionSuite.standard:
        canvas.drawRRect(RRect.fromRectXY(fill, r, r), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => true;
}

// ---------------------------------------------------------------------------
// 32 · empty, no results, not linked, no permission
// ---------------------------------------------------------------------------

/// Explains why there is nothing here and what to do next. Static: it only
/// takes part in the page's own entrance. The primary action carries the
/// suite's quiet static emphasis (rail underline, scan brackets, glow edge)
/// so the next step is easy to find, without pulsing or looping.
class SuiteEmptyState extends StatelessWidget {
  const SuiteEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(icon, size: 28, color: p.textSecondary),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: p.textSecondary),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 4),
            CustomPaint(
              foregroundPainter: onAction == null
                  ? null
                  : _ActionEmphasis(data),
              child: SuitePressable(
                kind: PressableKind.secondary,
                minHeight: 30,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionEmphasis extends CustomPainter {
  _ActionEmphasis(this.data);
  final InteractionData data;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.drawRect(
          Rect.fromLTWH(8, size.height + 3, size.width - 16, 1.5),
          Paint()..color = p.edge(0.7),
        );
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.inflate(4),
          color: p.edge(0.7),
          length: 6,
          width: 1.5,
        );
      case InteractionSuite.glow:
        paintGlowStrokes(
          canvas,
          suiteRadius(data.suite, 6).toRRect(rect),
          p.accent,
          0.35,
        );
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_ActionEmphasis old) => old.data != data;
}
