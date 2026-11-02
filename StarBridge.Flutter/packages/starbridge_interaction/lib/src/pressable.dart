import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'burst.dart';
import 'effect_host.dart';
import 'keyboard_modality.dart';
import 'painters.dart';
import 'suite.dart';

/// What the pressable represents. It sets the base fill, the foreground
/// colour and which suite decorations apply.
enum PressableKind {
  primary,
  secondary,
  danger,
  icon,
  row,
  card,
  menuItem,

  /// Side navigation entry. Selection is drawn by [SuiteSelectionTrack].
  navItem,

  /// Tab or segmented option. Selection is drawn by [SuiteSelectionTrack].
  tab,
}

/// Animated state handed to [SuitePressable.builder].
@immutable
class PressableVisual {
  const PressableVisual({
    required this.hover,
    required this.pressed,
    required this.focused,
    required this.selected,
    required this.enabled,
    required this.foreground,
  });

  /// 0 → 1 hover progress.
  final double hover;
  final double pressed;
  final bool focused;
  final bool selected;
  final bool enabled;

  /// Text and icon colour for the current state.
  final Color foreground;
}

/// Hover, press, focus and selection feedback for one control, in the
/// current suite. Keyboard activation runs [onPressed] without decoration;
/// the focus frame stays. Disabled controls never play press effects.
///
/// In the standard suite this is a Material [InkWell] with ink ripple, i.e.
/// the client's current behaviour.
///
/// Pointer presses always keep their suite feedback, including rapid
/// clicks. Only passive [flashToken] updates explicitly opting into
/// [coalesceDataUpdates] can hold one capped layer and settle after silence.
class SuitePressable extends StatefulWidget {
  const SuitePressable({
    required this.kind,
    this.onPressed,
    this.onActivate,
    this.child,
    this.builder,
    this.selected = false,
    this.baseRadius = 6,
    this.padding = EdgeInsets.zero,
    this.minHeight = 0,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticSelected,
    this.semanticFocused,
    this.excludeChildSemantics = false,
    this.flashToken,
    this.coalesceDataUpdates = false,
    this.hoverFace = true,
    super.key,
  }) : assert(child != null || builder != null);

  final PressableKind kind;
  final VoidCallback? onPressed;

  /// Like [onPressed] but reports whether a pointer or the keyboard
  /// activated the control. Used by selection tracks.
  final ValueChanged<InteractionSource>? onActivate;
  final Widget? child;

  /// Builds content that reacts to hover (e.g. the rail icon nudge). Only
  /// rebuilt while the hover or press value is changing.
  final Widget Function(BuildContext context, PressableVisual visual)? builder;
  final bool selected;
  final double baseRadius;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  /// Read-screen projection can differ from visual fill when a shared track
  /// paints selection outside this target.
  final bool? semanticSelected;
  final bool? semanticFocused;
  final bool excludeChildSemantics;

  /// Change this value to play the data-update flash (rows and cards).
  final Object? flashToken;

  /// Opt in only for passive data (e.g. background member status updates).
  /// Never coalesces clicks, selections, callbacks or network requests.
  final bool coalesceDataUpdates;

  /// Suites only: false leaves hover to a surface that already draws it
  /// (a hover card's lift and outline), so the pressable adds no second hover
  /// face. Press feedback and the keyboard focus ring are unchanged; the
  /// standard suite keeps its native ink.
  final bool hoverFace;

  @override
  State<SuitePressable> createState() => _SuitePressableState();
}

class _SuitePressableState extends State<SuitePressable>
    with TickerProviderStateMixin {
  late final _hover = AnimationController(vsync: this);
  late final _press = AnimationController(vsync: this);
  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());

  /// Presence of the continuous-state layer.
  late final _flow = AnimationController(vsync: this);
  late final _burst = BurstTracker(vsync: this, onChanged: _onBurst);
  final _fx = GlobalKey<EffectHostState>();
  bool _focused = false;
  bool _hovering = false;
  bool _disposing = false;

  /// The focus detector asked for a highlight; [_focused] shows it only
  /// while the keyboard drives input, so focus handed back after a click
  /// (a closing menu or dialog) paints no ring.
  bool _focusRequested = false;

  void _showFocus(bool value) {
    if (value != _focusRequested) {
      _focusRequested = value;
      final modality = KeyboardModality.listenable;
      value
          ? modality.addListener(_modalityChanged)
          : modality.removeListener(_modalityChanged);
    }
    _modalityChanged();
  }

  void _modalityChanged() {
    final focused = _focusRequested && KeyboardModality.showsFocus;
    if (focused != _focused && mounted && !_disposing) {
      setState(() => _focused = focused);
    }
  }

  /// Standard suite: set by InkWell.onTapDown, which only pointers trigger.
  bool _pointerTap = false;

  bool get _enabled => widget.onPressed != null || widget.onActivate != null;

  void _activate(InteractionSource source) {
    if (source == InteractionSource.keyboard) {
      _clearDataFeedback();
      _press.value = 0;
      _hover.value = _hovering ? 1 : 0;
      _fx.currentState?.clear();
    }
    if (widget.onActivate != null) {
      widget.onActivate!(source);
    } else {
      widget.onPressed?.call();
    }
  }

  bool get _isButton =>
      widget.kind == PressableKind.primary ||
      widget.kind == PressableKind.secondary ||
      widget.kind == PressableKind.danger ||
      widget.kind == PressableKind.icon;

  @override
  void didUpdateWidget(SuitePressable old) {
    super.didUpdateWidget(old);
    if (old.coalesceDataUpdates && !widget.coalesceDataUpdates) {
      _clearDataFeedback();
      _fx.currentState?.clear();
    }
    if (widget.flashToken != old.flashToken && old.flashToken != null) {
      _playFlash();
    }
    if (!_enabled && _hovering) _setHover(false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = InteractionScope.of(context);
    _press.duration = data.timed(data.motion.press);
    if (!data.animates || data.suite == InteractionSuite.standard) {
      _hover.value = _hovering ? 1 : 0;
      _press.value = 0;
      _clearDataFeedback();
    }
  }

  @override
  void initState() {
    super.initState();
    KeyboardModality.retain();
  }

  @override
  void dispose() {
    _disposing = true;
    if (_focusRequested) {
      KeyboardModality.listenable.removeListener(_modalityChanged);
    }
    KeyboardModality.release();
    _ownedFocus?.dispose();
    _hover.dispose();
    _press.dispose();
    _flow.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _onBurst(bool active) {
    if (!mounted) return;
    final data = InteractionScope.of(context);
    if (!data.animates) return;
    _flow.duration = active ? BurstMotion.enter : BurstMotion.settle;
    active ? _flow.forward() : _flow.reverse();
  }

  void _clearDataFeedback() {
    _burst.reset();
    _flow.value = 0;
  }

  /// Records a passive data event only when the caller explicitly opts in.
  bool _continuous() {
    final data = InteractionScope.of(context);
    if (!widget.coalesceDataUpdates ||
        !data.animates ||
        data.suite == InteractionSuite.standard) {
      return false;
    }
    return _burst.hit();
  }

  void _setHover(bool on) {
    if (!widget.hoverFace) on = false;
    if (on == _hovering) return;
    _hovering = on;
    final data = InteractionScope.of(context);
    _hover.duration = data.timed(data.motion.hover);
    on ? _hover.forward() : _hover.reverse();
    if (on &&
        widget.kind == PressableKind.card &&
        data.suite == InteractionSuite.scan) {
      _fx.currentState?.play(TransientEffect.scanLine);
    }
  }

  void _down(TapDownDetails d) {
    if (!_enabled) return;
    // Active input never contributes to or inherits a passive-data burst.
    _clearDataFeedback();
    _press.value = 1;
    final data = InteractionScope.of(context);
    if (!_isButton) return;
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? Size.zero;
    switch (data.suite) {
      case InteractionSuite.scan:
        _fx.currentState?.play(TransientEffect.beam);
      case InteractionSuite.glow:
        _fx.currentState?.play(
          TransientEffect.ring,
          at: d.localPosition,
          // Ring radius ends near half the button size: a local cue, not a wave.
          ringScale: math.min(size.width / 2, size.height * 1.4) / 9,
        );
      case InteractionSuite.standard || InteractionSuite.rail:
        break;
    }
  }

  void _up() {
    // Gesture disposal may cancel a pending press after this element is
    // deactivated. Do not look up ancestors or touch disposed controllers.
    if (!mounted || _disposing) return;
    _press.reverse();
  }

  void _playFlash() {
    final fx = _fx.currentState;
    if (fx == null) return;
    if (_continuous()) {
      fx.clear();
      return;
    }
    switch (InteractionScope.of(context).suite) {
      case InteractionSuite.rail:
        fx.play(TransientEffect.sweep);
      case InteractionSuite.scan:
        fx
          ..play(TransientEffect.beam)
          ..play(TransientEffect.scanLine);
      case InteractionSuite.glow:
        fx.play(TransientEffect.pulse);
      case InteractionSuite.standard:
        break;
    }
  }

  Color _foreground(InteractionPalette p, double hover) {
    if (!_enabled) return p.textDisabled;
    return switch (widget.kind) {
      PressableKind.primary => p.onAccent,
      PressableKind.danger => p.onDanger,
      PressableKind.secondary || PressableKind.card => p.textPrimary,
      PressableKind.icon ||
      PressableKind.row ||
      PressableKind.menuItem ||
      PressableKind.navItem ||
      PressableKind.tab =>
        widget.selected
            ? p.textPrimary
            : Color.lerp(p.textSecondary, p.textPrimary, hover)!,
    };
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final radius = suiteRadius(data.suite, widget.baseRadius);
    final content = data.suite == InteractionSuite.standard
        ? _buildStandard(context, data, radius)
        : _buildSuite(context, data, radius);
    return Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.semanticSelected ?? widget.selected,
      focused: widget.semanticFocused,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeChildSemantics,
      // Assistive activation is an instant command, never a pointer gesture.
      onTap: _enabled ? () => _activate(InteractionSource.keyboard) : null,
      child: content,
    );
  }

  Widget _content(BuildContext context, InteractionPalette p) {
    Widget inner(double hover) {
      final visual = PressableVisual(
        hover: hover,
        pressed: _press.value,
        focused: _focused,
        selected: widget.selected,
        enabled: _enabled,
        foreground: _foreground(p, hover),
      );
      final child = widget.builder?.call(context, visual) ?? widget.child!;
      return IconTheme.merge(
        data: IconThemeData(color: visual.foreground),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: visual.foreground),
          child: child,
        ),
      );
    }

    final body = AnimatedBuilder(
      animation: _hover,
      builder: (context, _) => inner(_hover.value),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Padding(padding: widget.padding, child: body),
    );
  }

  Widget _buildStandard(
    BuildContext context,
    InteractionData data,
    BorderRadius radius,
  ) {
    final p = data.palette;
    final fill = _baseFill(p);
    // InkWell turns Enter/Space into a ripple. Keyboard activation is meant
    // to be instant and static, so these keys are claimed here (closer to
    // the focused InkWell than the app-wide shortcuts) and activate directly.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _KeyActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _KeyActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): _KeyActivateIntent(),
      },
      child: Actions(
        actions: {
          _KeyActivateIntent: CallbackAction<_KeyActivateIntent>(
            onInvoke: (_) {
              if (_enabled) _activate(InteractionSource.keyboard);
              return null;
            },
          ),
        },
        child: data.animates
            ? _standardInk(context, data, radius, p, fill)
            : _staticStandard(context, radius, p, fill),
      ),
    );
  }

  Widget _standardInk(
    BuildContext context,
    InteractionData data,
    BorderRadius radius,
    InteractionPalette p,
    Color? fill,
  ) {
    return FocusableActionDetector(
      enabled: _enabled,
      focusNode: _focus,
      autofocus: widget.autofocus,
      onShowFocusHighlight: _showFocus,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            // Focus feedback is immediate. InkWell's focus highlight would
            // otherwise start a native fade on the first keyboard input.
            color: _focused
                ? Color.alphaBlend(
                    _isButton
                        ? _standardOverlay(p).resolve({WidgetState.focused})!
                        : p.focusRing.withValues(alpha: 0.14),
                    fill ?? Colors.transparent,
                  )
                : fill,
            borderRadius: radius,
            border: _baseBorder(p),
          ),
          child: InkWell(
            excludeFromSemantics: true,
            onTapDown: !_enabled
                ? null
                : (_) {
                    _pointerTap = true;
                    if (_enabled) _focus.requestFocus();
                  },
            onTapCancel: () => _pointerTap = false,
            onTap: _enabled
                ? () {
                    final source = _pointerTap
                        ? InteractionSource.pointer
                        : InteractionSource.keyboard;
                    _pointerTap = false;
                    _activate(source);
                  }
                : null,
            onHover: _setHover,
            // The outer detector is the single focus owner; mouse ink stays
            // native, but cannot create its own keyboard/focus highlight ticker.
            canRequestFocus: false,
            borderRadius: radius,
            focusColor: p.focusRing.withValues(alpha: 0.14),
            // Buttons mirror the client's themed overlay (pressed 20 %,
            // focused 14 %, hovered 9 %); rows keep the theme defaults.
            overlayColor: _isButton ? _standardOverlay(p) : null,
            splashFactory: data.animates
                ? InkRipple.splashFactory
                : NoSplash.splashFactory,
            // An explicitly labelled row may contain independent actions
            // (e.g. an avatar). Do not let InkWell's non-focusable internal
            // Focus merge those actions with the rest of the row's content.
            child:
                widget.semanticLabel?.isNotEmpty == true &&
                    !widget.excludeChildSemantics
                ? Semantics(
                    explicitChildNodes: true,
                    child: _content(context, p),
                  )
                : _content(context, p),
          ),
        ),
      ),
    );
  }

  WidgetStateProperty<Color?> _standardOverlay(InteractionPalette p) {
    final base = switch (widget.kind) {
      PressableKind.primary => p.onAccent,
      PressableKind.danger => p.onDanger,
      _ => p.accent,
    };
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return base.withValues(alpha: 0.20);
      }
      if (states.contains(WidgetState.focused)) {
        return base.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered)) {
        return base.withValues(alpha: 0.09);
      }
      return null;
    });
  }

  /// No native InkHighlight ticker under reduced motion. NoSplash alone only
  /// suppresses the press ripple, not focus/hover fade-in after menu return.
  /// Keep the same target, focus owner and instantaneous state fills instead.
  Widget _staticStandard(
    BuildContext context,
    BorderRadius radius,
    InteractionPalette p,
    Color? fill,
  ) => FocusableActionDetector(
    enabled: _enabled,
    focusNode: _focus,
    autofocus: widget.autofocus,
    mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
    onShowFocusHighlight: _showFocus,
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          if (_enabled) _activate(InteractionSource.keyboard);
          return null;
        },
      ),
    },
    child: Builder(
      builder: (_) => MouseRegion(
        onEnter: (_) => _setHover(_enabled),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled
              ? (details) {
                  _down(details);
                }
              : null,
          onTapUp: (_) => _up(),
          onTapCancel: _up,
          onTap: _enabled ? () => _activate(InteractionSource.pointer) : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_hover, _press]),
            builder: (context, _) {
              final states = <WidgetState>{
                if (_focused) WidgetState.focused,
                if (_hovering) WidgetState.hovered,
                if (_press.value > 0) WidgetState.pressed,
              };
              final Color? overlay = !_enabled
                  ? null
                  : _isButton
                  ? _standardOverlay(p).resolve(states)
                  : states.contains(WidgetState.pressed)
                  ? Theme.of(context).highlightColor
                  : states.contains(WidgetState.focused)
                  ? p.focusRing.withValues(alpha: 0.14)
                  : states.contains(WidgetState.hovered)
                  ? Theme.of(context).hoverColor
                  : null;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: overlay == null
                      ? fill
                      : fill == null
                      ? overlay
                      : Color.alphaBlend(overlay, fill),
                  borderRadius: radius,
                  border: _baseBorder(p),
                ),
                child: _content(context, p),
              );
            },
          ),
        ),
      ),
    ),
  );

  Color? _baseFill(InteractionPalette p) => switch (widget.kind) {
    PressableKind.primary => _enabled ? p.accent : p.raised,
    PressableKind.danger => _enabled ? p.danger : p.raised,
    PressableKind.secondary || PressableKind.card => p.raised,
    PressableKind.row ||
    PressableKind.menuItem => widget.selected ? p.selectedFill : null,
    PressableKind.icon || PressableKind.navItem || PressableKind.tab => null,
  };

  Border? _baseBorder(InteractionPalette p) => switch (widget.kind) {
    PressableKind.secondary ||
    PressableKind.card ||
    PressableKind.icon => Border.all(color: p.border),
    _ => null,
  };

  Widget _buildSuite(
    BuildContext context,
    InteractionData data,
    BorderRadius radius,
  ) {
    final p = data.palette;
    final repaint = Listenable.merge([_hover, _press, _flow]);
    final painted = CustomPaint(
      painter: _FacePainter(
        repaint: repaint,
        state: this,
        data: data,
        radius: radius,
      ),
      foregroundPainter: _EdgePainter(
        repaint: repaint,
        state: this,
        data: data,
        radius: radius,
      ),
      child: _content(context, p),
    );
    final transformed = AnimatedBuilder(
      animation: repaint,
      child: painted,
      builder: (context, child) {
        final pr = _press.value, h = _hover.value;
        final m = Matrix4.identity();
        if (_isButton && data.suite == InteractionSuite.rail) {
          m.translateByDouble(0, pr, 0, 1);
        }
        if (widget.kind == PressableKind.card &&
            data.suite == InteractionSuite.glow) {
          m.translateByDouble(0, -2 * h, 0, 1);
        }
        final scale = !_isButton
            ? 1.0
            : switch (data.suite) {
                InteractionSuite.rail => 1 - 0.02 * pr,
                InteractionSuite.glow => 1 - 0.03 * pr,
                _ => 1.0,
              };
        return Transform(
          transform: m,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
    return FocusableActionDetector(
      enabled: _enabled,
      focusNode: _focus,
      autofocus: widget.autofocus,
      mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: _showFocus,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate(InteractionSource.keyboard);
            return null;
          },
        ),
      },
      // Hover comes from a plain MouseRegion: FocusableActionDetector only
      // reports hover in keyboard highlight mode.
      child: MouseRegion(
        onEnter: (_) => _setHover(_enabled),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTapDown: _down,
          onTapUp: (_) => _up(),
          onTapCancel: _up,
          onTap: _enabled ? () => _activate(InteractionSource.pointer) : null,
          child: EffectHost(
            key: _fx,
            borderRadius: radius,
            bracketLength: widget.kind == PressableKind.card ? 12 : 7,
            child: transformed,
          ),
        ),
      ),
    );
  }
}

/// Fill behind the content: base fill plus hover/press/selection faces.
class _FacePainter extends CustomPainter {
  _FacePainter({
    required Listenable repaint,
    required this.state,
    required this.data,
    required this.radius,
  }) : super(repaint: repaint);

  final _SuitePressableState state;
  final InteractionData data;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final w = state.widget;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    final h = state._hover.value, pr = state._press.value;
    final enabled = state._enabled;

    final base = state._baseFill(p);
    if (base != null) {
      var fill = base;
      if (enabled &&
          (w.kind == PressableKind.primary || w.kind == PressableKind.danger)) {
        fill = Color.lerp(
          base,
          p.isDark ? Colors.white : Colors.black,
          0.12 * h,
        )!;
      } else if (enabled &&
          (w.kind == PressableKind.secondary || w.kind == PressableKind.card)) {
        fill = Color.lerp(base, p.accent, 0.08 * h)!;
      }
      canvas.drawRRect(rrect, Paint()..color = fill);
    }

    final rowLike =
        w.kind == PressableKind.row ||
        w.kind == PressableKind.menuItem ||
        w.kind == PressableKind.navItem;
    switch (data.suite) {
      case InteractionSuite.rail:
        if (w.kind == PressableKind.tab && pr > 0) {
          // A confirmed/current tab still acknowledges each active press.
          // Selection remains on the external track; do not add another fill
          // or replay navigation when the owner stays on the same destination.
          canvas.drawRRect(rrect, Paint()..color = p.light(0.12 * pr));
        }
        if (rowLike) {
          if (w.selected && w.kind != PressableKind.navItem) {
            paintRailFace(canvas, rrect, p.accent, p.isDark ? 0.26 : 0.18);
          }
          if (pr > 0) {
            canvas.drawRRect(rrect, Paint()..color = p.light(0.12 * pr));
          }
        }
      case InteractionSuite.scan:
        if (rowLike && w.selected && w.kind != PressableKind.navItem) {
          canvas.drawRRect(
            rrect,
            Paint()..color = p.selectedFill.withValues(alpha: 0.85),
          );
        }
        if (rowLike && h > 0) {
          canvas.drawRRect(rrect, Paint()..color = p.light(0.06 * h));
        }
      case InteractionSuite.glow:
        if (rowLike) {
          final selected = w.selected && w.kind != PressableKind.navItem;
          paintSideGlow(
            canvas,
            rrect,
            p.accent,
            (selected ? 0.32 : 0) + 0.16 * h + 0.1 * pr,
          );
        }
        if (w.kind == PressableKind.tab && (h > 0 || pr > 0)) {
          final glowRect = Rect.fromLTWH(
            0,
            size.height * 0.4,
            size.width,
            size.height * 0.6,
          );
          canvas.drawRect(
            glowRect,
            Paint()
              ..shader = RadialGradient(
                center: Alignment.bottomCenter,
                radius: 0.9,
                colors: [p.light(0.22 * math.max(h, pr)), p.light(0)],
              ).createShader(glowRect),
          );
        }
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) => true;
}

/// Lines, brackets, glows and the focus frame in front of the content.
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required Listenable repaint,
    required this.state,
    required this.data,
    required this.radius,
  }) : super(repaint: repaint);

  final _SuitePressableState state;
  final InteractionData data;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final w = state.widget;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    final h = state._hover.value, pr = state._press.value;
    final button = state._isButton;
    final onFill =
        w.kind == PressableKind.primary || w.kind == PressableKind.danger;

    final border = state._baseBorder(p);
    if (border != null) {
      var c = border.top.color;
      if (data.suite == InteractionSuite.rail && state._enabled) {
        c = Color.lerp(c, p.edge(), h)!;
      } else if (data.suite == InteractionSuite.glow && state._enabled) {
        c = Color.lerp(c, p.edge(0.8), h)!;
      }
      canvas.drawRRect(
        rrect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = c,
      );
    }

    if (state._enabled) {
      switch (data.suite) {
        case InteractionSuite.rail:
          if (button) {
            final lineColor = onFill ? const Color(0xFFE8F7FF) : p.edge();
            canvas.save();
            canvas.clipRRect(rrect);
            if (h > 0) {
              canvas.drawRect(
                Rect.fromLTWH(0, 0, size.width, 1),
                Paint()
                  ..color = (onFill ? Colors.white : p.edge()).withValues(
                    alpha: 0.55 * h,
                  ),
              );
            }
            paintEdgeLine(canvas, rect, lineColor, scale: h);
            canvas.restore();
            if (pr > 0) {
              if (p.isDark) {
                paintGlowStrokes(canvas, rrect, p.edge(), pr);
              } else {
                canvas.drawRRect(
                  rrect.inflate(1),
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 2
                    ..color = p.accent.withValues(alpha: pr),
                );
              }
            }
          } else if (w.kind == PressableKind.card) {
            canvas.save();
            canvas.clipRRect(rrect);
            paintEdgeLine(canvas, rect, p.edge(), scale: h, top: true);
            canvas.restore();
          } else if (w.kind == PressableKind.tab) {
            if (!w.selected) {
              paintEdgeLine(
                canvas,
                Rect.fromLTRB(8, 0, size.width - 8, size.height),
                p.edge(0.45),
                scale: h,
              );
            }
          } else {
            final selected = w.selected && w.kind != PressableKind.navItem;
            if (selected) {
              paintSideBar(
                canvas,
                rect,
                p.edge(),
                inset: 9,
                glow: p.isDark ? p.edge() : null,
              );
            } else {
              paintSideBar(canvas, rect, p.edge(0.55), scale: h, inset: 9);
            }
          }
        case InteractionSuite.scan:
          if (button) {
            final inset = pr > 0 ? 1.0 : 4 - 2 * h;
            paintBrackets(
              canvas,
              rect.deflate(inset),
              color: (onFill ? p.onAccent : p.edge()).withValues(
                alpha: math.max(h, pr),
              ),
            );
          } else if (w.kind == PressableKind.card) {
            paintBrackets(
              canvas,
              rect.deflate(6 - 3 * h),
              color: p.edge(h),
              length: 12,
            );
          } else if (w.kind == PressableKind.menuItem) {
            if (h > 0) {
              final paint = Paint()..color = p.edge(h);
              canvas.drawRect(Rect.fromLTWH(0, 0, 2, size.height), paint);
              canvas.drawRect(
                Rect.fromLTWH(size.width - 2, 0, 2, size.height),
                paint,
              );
            }
          } else {
            final selected = w.selected && w.kind == PressableKind.row;
            final alpha = selected ? 1.0 : 0.45 * h;
            final inset = selected ? 3.0 : 2.0;
            if (w.kind != PressableKind.navItem &&
                    w.kind != PressableKind.tab ||
                !w.selected) {
              paintBrackets(
                canvas,
                rect.deflate(pr > 0 ? 1 : inset),
                color: p.edge(math.max(alpha, 0.6 * pr)),
              );
            }
          }
        case InteractionSuite.glow:
          if (button) {
            paintGlowStrokes(
              canvas,
              rrect,
              onFill ? p.edge() : p.edge(0.8),
              h * (onFill ? 1 : 0.8),
            );
          } else if (w.kind == PressableKind.card) {
            paintGlowStrokes(canvas, rrect, p.edge(0.7), h * 0.7);
          }
        case InteractionSuite.standard:
          break;
      }
    }

    final flow = state._flow.value;
    if (flow > 0 && state._enabled) {
      final rowLike = !button && w.kind != PressableKind.card;
      switch (data.suite) {
        case InteractionSuite.rail:
          if (button) {
            canvas.save();
            canvas.clipRRect(rrect);
            paintEdgeLine(
              canvas,
              rect,
              (onFill ? const Color(0xFFE8F7FF) : p.edge()).withValues(
                alpha: flow,
              ),
            );
            canvas.restore();
          } else if (rowLike) {
            paintSideBar(canvas, rect, p.edge(flow), inset: 9);
          } else {
            canvas.save();
            canvas.clipRRect(rrect);
            paintEdgeLine(canvas, rect, p.edge(flow), top: true);
            canvas.restore();
          }
        case InteractionSuite.scan:
          paintBrackets(
            canvas,
            rect.deflate(button ? 2 : 3),
            color: (onFill ? p.onAccent : p.edge()).withValues(alpha: flow),
            length: w.kind == PressableKind.card ? 12 : 7,
          );
        case InteractionSuite.glow:
          paintGlowStrokes(
            canvas,
            rrect,
            onFill ? p.edge() : p.edge(0.8),
            0.6 * flow,
          );
        case InteractionSuite.standard:
          break;
      }
    }

    if (state._focused) {
      canvas.drawRRect(
        rrect.inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

class _KeyActivateIntent extends Intent {
  const _KeyActivateIntent();
}
