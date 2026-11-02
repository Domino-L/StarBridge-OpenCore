import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'counter.dart';
import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

/// Horizontal value slider. The handle follows the pointer exactly (no
/// easing, no elastic lag) and the value reported is always the real one;
/// only the surrounding marks animate.
///
/// Rail: the filled part carries a lit edge and, while dragging, a position
/// line marks the handle across the control. Scan: the track shows ticks,
/// the handle is a bracketed square that locks on release, the nearest tick
/// lights while dragging. Glow: the handle carries a local halo while hovered
/// or dragged. Standard: a plain track and round handle.
///
/// Arrow keys step by one division (or 5 %), Home/End jump to the ends,
/// instantly in every suite.
class SuiteSlider extends StatefulWidget {
  const SuiteSlider({
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.onChangeCancel,
    this.onInputSource,
    this.focusNode,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.keyboardStep,
    this.semanticLabel,
    this.valueLabel,
    super.key,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onChangeCancel;

  /// Called synchronously before a value callback; never a saved-value owner.
  final ValueChanged<InteractionSource>? onInputSource;
  final FocusNode? focusNode;
  final double min;
  final double max;
  final int? divisions;

  /// Value-unit keyboard/reader step, independent of pointer snapping/ticks.
  final double? keyboardStep;
  final String? semanticLabel;

  /// Text read out for the current value (e.g. "60 %").
  final String Function(double value)? valueLabel;

  @override
  State<SuiteSlider> createState() => _SuiteSliderState();
}

class _SuiteSliderState extends State<SuiteSlider>
    with TickerProviderStateMixin {
  /// Engagement: hover or drag (0 → 1).
  late final _engage = AnimationController(vsync: this);

  /// One-shot lock/settle after a drag ends.
  late final _release = AnimationController(vsync: this);
  bool _hover = false;
  bool _dragging = false;
  bool _focused = false;
  double? _pendingValue;
  bool _pointerCanceled = false;
  final _localFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _localFocus;

  final _boxKey = GlobalKey();

  double get _width =>
      (_boxKey.currentContext?.findRenderObject() as RenderBox?)?.size.width ??
      200;

  bool get _enabled => widget.onChanged != null;
  double get _t =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) {
      _engage.value = (_hover || _dragging) ? 1 : 0;
      _release.reset();
    }
  }

  @override
  void didUpdateWidget(SuiteSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _pendingValue = null;
    if (!_enabled) {
      _pendingValue = null;
      _dragging = false;
      _engage.reset();
      _release.reset();
    }
  }

  @override
  void dispose() {
    _engage.dispose();
    _release.dispose();
    _localFocus.dispose();
    super.dispose();
  }

  void _setEngaged() {
    final data = InteractionScope.of(context);
    final on = _enabled && (_hover || _dragging);
    _engage.duration = data.timed(
      on ? data.motion.hover : const Duration(milliseconds: 160),
    );
    on ? _engage.forward() : _engage.reverse();
  }

  double _snap(double t) {
    final d = widget.divisions;
    final v = widget.min + (widget.max - widget.min) * t.clamp(0.0, 1.0);
    if (d == null || d <= 0) return v;
    final step = (widget.max - widget.min) / d;
    return widget.min + ((v - widget.min) / step).round() * step;
  }

  void _setFromLocal(double dx, double width) {
    const pad = 9.0;
    final visual = ((dx - pad) / (width - pad * 2)).clamp(0.0, 1.0);
    final t = Directionality.of(context) == TextDirection.rtl
        ? 1 - visual
        : visual;
    final v = _snap(t);
    _pendingValue = v;
    widget.onInputSource?.call(InteractionSource.pointer);
    if (v != widget.value) widget.onChanged?.call(v);
  }

  void _end() {
    if (_pointerCanceled) return;
    setState(() => _dragging = false);
    _setEngaged();
    if (!_enabled) return;
    final value = _pendingValue ?? widget.value;
    _pendingValue = null;
    widget.onInputSource?.call(InteractionSource.pointer);
    widget.onChangeEnd?.call(value);
    final data = InteractionScope.of(context);
    if (data.animates && data.suite != InteractionSuite.standard) {
      _release
        ..duration = const Duration(milliseconds: 180)
        ..forward(from: 0);
    }
  }

  void _cancel() {
    if (_pointerCanceled) return;
    _pointerCanceled = true;
    setState(() => _dragging = false);
    _pendingValue = null;
    _release.reset();
    _setEngaged();
    widget.onInputSource?.call(InteractionSource.pointer);
    widget.onChangeCancel?.call();
  }

  void _instant() {
    _engage.reset();
    _release.reset();
    widget.onInputSource?.call(InteractionSource.keyboard);
  }

  double _stepped(int dir) {
    final d = widget.divisions;
    final step =
        widget.keyboardStep ??
        (d != null && d > 0
            ? (widget.max - widget.min) / d
            : (widget.max - widget.min) * 0.05);
    return (widget.value + dir * step).clamp(widget.min, widget.max);
  }

  void _step(int dir) {
    if (!_enabled) return;
    _instant();
    final v = _stepped(dir);
    if (v != widget.value) {
      widget.onChanged!(v);
      widget.onChangeEnd?.call(v);
    }
  }

  void _jump(double v) {
    if (!_enabled) return;
    _instant();
    if (v == widget.value) return;
    widget.onChanged!(v);
    widget.onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    String text(double v) => widget.valueLabel?.call(v) ?? v.toStringAsFixed(2);
    final label = text(widget.value);
    return Semantics(
      slider: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      value: label,
      increasedValue: text(_stepped(1)),
      decreasedValue: text(_stepped(-1)),
      onIncrease: _enabled ? () => _step(1) : null,
      onDecrease: _enabled ? () => _step(-1) : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: _focus,
        mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): _SlideIntent(
            rtl ? -1 : 1,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowUp): const _SlideIntent(
            1,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _SlideIntent(
            rtl ? 1 : -1,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              const _SlideIntent(-1),
          const SingleActivator(LogicalKeyboardKey.home): const _SlideIntent(
            -100,
          ),
          const SingleActivator(LogicalKeyboardKey.end): const _SlideIntent(
            100,
          ),
        },
        actions: {
          _SlideIntent: CallbackAction<_SlideIntent>(
            onInvoke: (i) {
              if (i.dir == -100) {
                _jump(widget.min);
              } else if (i.dir == 100) {
                _jump(widget.max);
              } else {
                _step(i.dir);
              }
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) {
            _hover = true;
            _setEngaged();
          },
          onExit: (_) {
            _hover = false;
            _setEngaged();
          },
          // Width is read from the render box at gesture time instead of a
          // LayoutBuilder, so the slider also works under intrinsic sizing.
          child: Listener(
            onPointerDown: (_) => _pointerCanceled = false,
            onPointerCancel: _enabled ? (_) => _cancel() : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _enabled
                  ? (d) {
                      _focus.requestFocus();
                      _setFromLocal(d.localPosition.dx, _width);
                    }
                  : null,
              onTapUp: _enabled ? (_) => _end() : null,
              onTapCancel: _enabled
                  ? () {
                      if (!_dragging) _cancel();
                    }
                  : null,
              onHorizontalDragStart: _enabled
                  ? (d) {
                      _focus.requestFocus();
                      _pointerCanceled = false;
                      setState(() => _dragging = true);
                      _release.reset();
                      _setEngaged();
                      _setFromLocal(d.localPosition.dx, _width);
                    }
                  : null,
              onHorizontalDragUpdate: _enabled
                  ? (d) => _setFromLocal(d.localPosition.dx, _width)
                  : null,
              onHorizontalDragEnd: _enabled ? (_) => _end() : null,
              child: SizedBox(
                key: _boxKey,
                width: double.infinity,
                height: 32,
                child: CustomPaint(
                  painter: _SliderPainter(
                    t: _t,
                    data: data,
                    rtl: rtl,
                    enabled: _enabled,
                    dragging: _dragging,
                    focused: _focused,
                    divisions: widget.divisions,
                    engage: _engage,
                    release: _release,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlideIntent extends Intent {
  const _SlideIntent(this.dir);
  final int dir;
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.t,
    required this.data,
    required this.rtl,
    required this.enabled,
    required this.dragging,
    required this.focused,
    required this.divisions,
    required this.engage,
    required this.release,
  }) : super(repaint: Listenable.merge([engage, release]));

  final double t;
  final InteractionData data;
  final bool rtl;
  final bool enabled;
  final bool dragging;
  final bool focused;
  final int? divisions;
  final Animation<double> engage;
  final Animation<double> release;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final suite = data.suite;
    final e = engage.value;
    const pad = 9.0;
    final cy = size.height / 2;
    final x = pad + (size.width - pad * 2) * (rtl ? 1 - t : t);
    final track = Rect.fromLTRB(pad, cy - 2, size.width - pad, cy + 2);
    final fill = Rect.fromLTRB(
      rtl ? x : pad,
      cy - 2,
      rtl ? size.width - pad : x,
      cy + 2,
    );
    final r = suite == InteractionSuite.scan ? 0.0 : 2.0;
    final accent = enabled ? p.accent : p.textDisabled;

    canvas.drawRRect(RRect.fromRectXY(track, r, r), Paint()..color = p.raised);
    canvas.drawRRect(
      RRect.fromRectXY(track, r, r).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = p.border.withValues(alpha: 0.7),
    );

    // Ticks (scan always shows them; others only for discrete sliders).
    final tickCount = divisions ?? (suite == InteractionSuite.scan ? 10 : 0);
    if (tickCount > 0) {
      for (var i = 0; i <= tickCount; i++) {
        final tx = pad + (size.width - pad * 2) * i / tickCount;
        final near = (tx - x).abs() < (size.width - pad * 2) / tickCount / 2;
        final lit = suite == InteractionSuite.scan && dragging && near;
        canvas.drawRect(
          Rect.fromLTWH(
            tx - 0.5,
            cy + 5,
            1,
            suite == InteractionSuite.scan ? 5 : 3,
          ),
          Paint()
            ..color = lit ? p.edge() : p.textSecondary.withValues(alpha: 0.45),
        );
      }
    }

    switch (suite) {
      case InteractionSuite.standard:
        canvas.drawRRect(RRect.fromRectXY(fill, r, r), Paint()..color = accent);
        if (e > 0) {
          canvas.drawCircle(
            Offset(x, cy),
            15,
            Paint()..color = accent.withValues(alpha: 0.12 * e),
          );
        }
        canvas.drawCircle(Offset(x, cy), 7, Paint()..color = accent);
      case InteractionSuite.rail:
        canvas.drawRect(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
              end: rtl ? Alignment.centerLeft : Alignment.centerRight,
              colors: [accent.withValues(alpha: 0.55), accent],
            ).createShader(track),
        );
        if (enabled) {
          canvas.drawRect(
            Rect.fromLTRB(fill.left, cy - 2, fill.right, cy - 1),
            Paint()..color = p.edge(0.4 + 0.6 * e),
          );
        }
        // Position line across the control while engaged.
        final settle = release.value > 0 && release.value < 1
            ? 1 - release.value
            : 0.0;
        final line = dragging ? 1.0 : settle;
        if (line > 0) {
          canvas.drawRect(
            Rect.fromLTWH(x - 0.5, 1, 1, size.height - 2),
            Paint()..color = p.edge(0.5 * line),
          );
        }
        final thumb = Rect.fromCenter(
          center: Offset(x, cy),
          width: 4,
          height: 16 + 2 * e,
        );
        if (e > 0 && p.isDark) {
          paintGlowStrokes(
            canvas,
            RRect.fromRectXY(thumb, 1, 1),
            p.edge(),
            0.6 * e,
          );
        }
        canvas.drawRRect(
          RRect.fromRectXY(thumb, 1, 1),
          Paint()..color = enabled ? p.edge() : p.textDisabled,
        );
      case InteractionSuite.scan:
        canvas.drawRect(fill, Paint()..color = accent);
        final box = Rect.fromCenter(
          center: Offset(x, cy),
          width: 10,
          height: 10,
        );
        canvas.drawRect(
          box,
          Paint()..color = enabled ? p.textPrimary : p.textDisabled,
        );
        final lock = release.value;
        final locking = lock > 0 && lock < 1;
        final inset = dragging
            ? -4.0
            : locking
            ? -4 - 3 * (1 - SuiteMotion.curve.transform(lock))
            : -4.0;
        final alpha = dragging || locking ? 1.0 : e;
        if (enabled && alpha > 0) {
          paintBrackets(
            canvas,
            box.deflate(inset),
            color: p.edge(alpha),
            length: 4,
            width: 1.5,
          );
        }
      case InteractionSuite.glow:
        canvas.drawRRect(RRect.fromRectXY(fill, r, r), Paint()..color = accent);
        if (enabled && p.isDark) {
          paintGlowStrokes(
            canvas,
            RRect.fromRectXY(fill, r, r),
            accent,
            0.25 + 0.3 * e,
          );
        }
        if (enabled && e > 0) {
          final halo = Rect.fromCircle(center: Offset(x, cy), radius: 16);
          canvas.drawOval(
            halo,
            Paint()
              ..shader = RadialGradient(colors: [p.light(0.42 * e), p.light(0)])
                  .createShader(halo),
          );
        }
        canvas.drawCircle(
          Offset(x, cy),
          7,
          Paint()..color = enabled ? Colors.white : p.textDisabled,
        );
        canvas.drawCircle(
          Offset(x, cy),
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = accent,
        );
    }

    if (focused) {
      canvas.drawCircle(
        Offset(x, cy),
        12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
  }

  @override
  bool shouldRepaint(_SliderPainter old) => true;
}

/// − value + stepper. Every press is an active operation and keeps its full
/// per-press feedback (the value uses [SuiteCounter] without coalescing).
class SuiteStepper extends StatelessWidget {
  const SuiteStepper({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
    this.semanticLabel,
    super.key,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = InteractionScope.of(context).palette;
    Widget btn(IconData icon, String label, int delta) {
      final next = value + delta;
      final ok = onChanged != null && next >= min && next <= max;
      return SuitePressable(
        kind: PressableKind.icon,
        minHeight: 30,
        padding: const EdgeInsets.all(6),
        semanticLabel: label,
        onPressed: ok ? () => onChanged!(next) : null,
        child: Icon(icon, size: 16),
      );
    }

    return Semantics(
      label: semanticLabel,
      value: '$value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          btn(Icons.remove, '减少', -1),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 32),
            child: Center(
              child: SuiteCounter(
                value: value,
                style: TextStyle(
                  fontFamily: 'Source Code Pro',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ),
          ),
          btn(Icons.add, '增加', 1),
        ],
      ),
    );
  }
}
