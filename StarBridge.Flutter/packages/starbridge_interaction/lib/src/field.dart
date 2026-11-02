import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'effect_host.dart';
import 'painters.dart';
import 'suite.dart';

/// Frame around a text input. The input itself is untouched: no per
/// character animation, IME, selection and undo work as usual.
///
/// Focus: rail grows a lit line along the bottom edge; scan locks corner
/// brackets onto the field (one scan line when focused by pointer); glow
/// shows a clear halo. Keyboard focus goes straight to the final frame.
/// [error] shows a static danger edge and marker in every suite.
class SuiteFieldFrame extends StatefulWidget {
  const SuiteFieldFrame({
    required this.focusNode,
    required this.child,
    this.error = false,
    this.height = 34,
    this.enabled = true,
    this.foregroundOnly = false,
    this.cursor = SystemMouseCursors.text,
    this.boundsResolver,
    this.paintExclusionResolver,
    this.errorResolver,
    super.key,
  });

  final FocusNode focusNode;
  final Widget child;
  final bool error;
  final double? height;
  final bool enabled, foregroundOnly;
  final MouseCursor cursor;
  final Rect Function(Size size)? boundsResolver;

  /// An existing native floating label may overlap the frame. Exclude only
  /// its paint bounds; focus, hit testing and semantics remain native.
  final Rect? Function()? paintExclusionResolver;

  /// Optional live paint-only projection (e.g. a native InputDecorator error).
  /// Read after bounds resolution; never runs validation or owns form state.
  /// An explicit [error] still takes precedence.
  final bool Function()? errorResolver;

  @override
  State<SuiteFieldFrame> createState() => _SuiteFieldFrameState();
}

class _SuiteFieldFrameState extends State<SuiteFieldFrame>
    with SingleTickerProviderStateMixin {
  late final _focus = AnimationController(vsync: this);
  final _fx = GlobalKey<EffectHostState>();
  bool _hover = false;

  bool _pendingPointer = false, _observing = false;
  InteractionSource _source = InteractionSource.keyboard;
  InteractionSuite? _suite;

  void _observe() {
    if (_observing) return;
    _observing = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerSeen);
    HardwareKeyboard.instance.addHandler(_keySeen);
  }

  void _unobserve() {
    if (!_observing) return;
    _observing = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerSeen);
    HardwareKeyboard.instance.removeHandler(_keySeen);
  }

  void _pointerSeen(PointerEvent event) {
    if (event is PointerDownEvent) _source = InteractionSource.pointer;
  }

  bool _keySeen(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _source = InteractionSource.keyboard;
      _pendingPointer = false;
      _fx.currentState?.clear();
      if (widget.focusNode.hasFocus) {
        _focus.value = widget.enabled ? 1 : 0;
      } else {
        _unobserve();
      }
    }
    return false; // Observe provenance; never consume an editor/shortcut key.
  }

  void _pointerDown() {
    if (!widget.enabled) return;
    _pendingPointer = true;
    _source = InteractionSource.pointer;
    _observe();
  }

  void _pointerEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingPointer = false;
      if (!widget.focusNode.hasFocus) _unobserve();
    });
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    _focus.value = widget.enabled && widget.focusNode.hasFocus ? 1 : 0;
    if (widget.enabled && widget.focusNode.hasFocus) _observe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-animation: stop and show the real
    // final frame right away (focused or not), plus clear any scan line.
    final data = InteractionScope.of(context);
    if (!data.animates || (_suite != null && _suite != data.suite)) {
      _focus.stop();
      _focus.value = widget.enabled && widget.focusNode.hasFocus ? 1 : 0;
      _fx.currentState?.clear();
    }
    _suite = data.suite;
  }

  @override
  void didUpdateWidget(SuiteFieldFrame old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
      _pendingPointer = false;
      _source = InteractionSource.keyboard;
      _fx.currentState?.clear();
      _focus.value = widget.enabled && widget.focusNode.hasFocus ? 1 : 0;
      widget.focusNode.hasFocus ? _observe() : _unobserve();
    }
    if (!widget.enabled) {
      _pendingPointer = false;
      _focus.value = 0;
      _fx.currentState?.clear();
      _unobserve();
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _unobserve();
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    final data = InteractionScope.of(context);
    final has = widget.focusNode.hasFocus;
    final pointer = has
        ? _pendingPointer
        : _source == InteractionSource.pointer;
    _pendingPointer = false;
    if (has) {
      _observe();
    } else {
      _fx.currentState?.clear();
      _unobserve();
    }
    _source = InteractionSource.keyboard;
    if (!widget.enabled) {
      _focus.value = 0;
      _unobserve();
      return;
    }
    if (!data.animates ||
        !pointer ||
        (widget.foregroundOnly && data.suite == InteractionSuite.standard)) {
      _fx.currentState?.clear();
      _focus.value = has ? 1 : 0;
      return;
    }
    if (!has) {
      _focus.duration = data.timed(data.motion.exit);
      _focus.reverse();
      return;
    }
    _focus.duration = data.motion.select;
    _focus.forward();
    if (data.suite == InteractionSuite.scan) {
      _fx.currentState?.play(TransientEffect.scanLine);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final radius = suiteRadius(data.suite, 6);
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (_) => _pointerDown(),
        onPointerUp: (_) => _pointerEnd(),
        onPointerCancel: (_) => _pointerEnd(),
        child: EffectHost(
          key: _fx,
          borderRadius: radius,
          boundsResolver: widget.boundsResolver,
          paintExclusionResolver: widget.paintExclusionResolver,
          child: CustomPaint(
            painter: widget.foregroundOnly
                ? null
                : _FieldPainter(this, data, radius, _focus),
            foregroundPainter: widget.foregroundOnly
                ? _FieldPainter(this, data, radius, _focus)
                : null,
            child: SizedBox(height: widget.height, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.s, this.data, this.radius, this.focus)
    : super(repaint: focus);

  final _SuiteFieldFrameState s;
  final InteractionData data;
  final BorderRadius radius;
  final Animation<double> focus;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    if (!s.widget.enabled ||
        (s.widget.foregroundOnly && data.suite == InteractionSuite.standard)) {
      return;
    }
    final f = SuiteMotion.curve.transform(focus.value);
    final rect = s.widget.boundsResolver?.call(size) ?? (Offset.zero & size);
    canvas.save();
    clipPaintExclusion(canvas, size, s.widget.paintExclusionResolver?.call());
    final rrect = radius.toRRect(rect);
    final error = s.widget.error || (s.widget.errorResolver?.call() ?? false);
    final focusColor = error ? p.danger : p.accent;

    if (!s.widget.foregroundOnly) {
      canvas.drawRRect(rrect, Paint()..color = p.surface);
    }
    var border = Color.lerp(p.border, p.textSecondary, s._hover ? 0.35 : 0)!;
    switch (data.suite) {
      case InteractionSuite.standard || InteractionSuite.glow:
        border = Color.lerp(border, focusColor, f)!;
      case InteractionSuite.rail:
        border = Color.lerp(border, focusColor.withValues(alpha: 0.6), f)!;
      case InteractionSuite.scan:
        border = Color.lerp(border, focusColor.withValues(alpha: 0.7), f)!;
    }
    if (error) border = p.danger;
    if (!s.widget.foregroundOnly) {
      canvas.drawRRect(
        rrect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = border,
      );
    }

    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.save();
        canvas.clipRRect(rrect);
        paintEdgeLine(
          canvas,
          rect,
          error ? p.danger : p.edge(),
          scale: f,
          glow: p.isDark && !error ? p.edge() : null,
        );
        canvas.restore();
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.inflate(7 - 4 * f),
          color: (error ? p.danger : p.edge()).withValues(alpha: f),
        );
      case InteractionSuite.glow:
        if (f > 0) {
          canvas.drawRRect(
            rrect.inflate(2),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = focusColor.withValues(alpha: 0.2 * f),
          );
          if (p.isDark) {
            paintGlowStrokes(canvas, rrect.inflate(3), focusColor, 0.5 * f);
          }
        }
      case InteractionSuite.standard:
        break;
    }

    if (error) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, 3, rect.height),
        Paint()..color = p.danger,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldPainter old) => true;
}
