import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'suite.dart';

/// Lightweight hint on hover or keyboard focus. Never blocks input (the
/// bubble ignores pointers) and never steals focus.
///
/// Timing: appears after [waitDuration]; while the user keeps browsing
/// (another suite tooltip closed less than 400 ms ago) the next one shows
/// without waiting. Keyboard focus shows it at once and without motion.
///
/// Rail: a short offset along the anchor direction plus a lit top edge.
/// Scan: short corner marks frame the bubble. Glow: a soft fade with a hint
/// of light. Standard: a plain fade. Exit is a quick fade in every suite.
class SuiteTooltip extends StatefulWidget {
  const SuiteTooltip({
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 450),
    this.excludeFromSemantics = false,
    this.showDuration = const Duration(milliseconds: 1500),
    this.onVisibilityChanged,
    this.consumeEscape = true,
    super.key,
  });

  final String message;
  final Widget child;
  final Duration waitDuration;
  final bool excludeFromSemantics;
  final Duration showDuration;

  /// Actual overlay lifetime, including its exit. Used by native child-window
  /// hosts to keep a visibility lease until the bubble is gone. Not a command.
  final ValueChanged<bool>? onVisibilityChanged;

  /// Keep the usual hint-only dismissal by default. A passive hint inside a
  /// modal can opt out so the same Escape also reaches its existing owner.
  final bool consumeEscape;

  @override
  State<SuiteTooltip> createState() => SuiteTooltipState();
}

class SuiteTooltipState extends State<SuiteTooltip>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// When the last suite tooltip closed, shared by all instances so the
  /// "continuous browsing" rule works across neighbouring controls.
  static DateTime _lastHidden = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether the latest user input was a key press. On desktop the highlight
  /// mode stays "traditional" for mouse users too, so it cannot tell keyboard
  /// focus from a menu or dialog handing focus back after a click; treating
  /// that as keyboard focus left the hint stuck after the pointer moved away.
  static bool _keyInput = false;
  static int _inputWatchers = 0;

  // A press or any mouse movement means the user is on the pointer again, so
  // an older key press (even Alt+Tab) no longer makes focus "keyboard" focus.
  static void _pointerInput(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerHoverEvent) {
      _keyInput = false;
    }
  }

  static bool _keyboardInput(KeyEvent event) {
    if (event is KeyDownEvent) _keyInput = true;
    return false;
  }

  // Shared by all live tooltips: installed with the first, removed with the
  // last, so nothing stays registered once no tooltip is mounted.
  static void _watchInput() {
    if (_inputWatchers++ > 0) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerInput);
    HardwareKeyboard.instance.addHandler(_keyboardInput);
  }

  static void _unwatchInput() {
    if (--_inputWatchers > 0) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerInput);
    HardwareKeyboard.instance.removeHandler(_keyboardInput);
  }

  final _portal = OverlayPortalController();
  late final _anim = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed) _hidePortal();
    });
  Timer? _wait;
  Timer? _dismiss;
  bool _instant = false;
  bool _visible = true;
  bool _hovered = false;
  bool _keyboardFocused = false;
  int _generation = 0;
  bool _reportedShowing = false;
  bool _watchingEscape = false;

  void _watchEscape() {
    if (_watchingEscape) return;
    _watchingEscape = true;
    FocusManager.instance.addEarlyKeyEventHandler(_escape);
  }

  void _unwatchEscape() {
    if (!_watchingEscape) return;
    _watchingEscape = false;
    FocusManager.instance.removeEarlyKeyEventHandler(_escape);
  }

  KeyEventResult _escape(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        (!_portal.isShowing && _wait == null)) {
      return KeyEventResult.ignored;
    }
    final currentRoute = ModalRoute.isCurrentOf(context) ?? true;
    _hide(instant: true);
    return currentRoute && widget.consumeEscape
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _reportShowing(bool showing) {
    if (_reportedShowing == showing) return;
    _reportedShowing = showing;
    widget.onVisibilityChanged?.call(showing);
  }

  /// Whether the bubble is currently showing (tests and lab).
  bool get isShowing =>
      _portal.isShowing && _anim.status != AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _watchInput();
    WidgetsBinding.instance.addObserver(this);
  }

  // The window losing focus sends no pointer exit; a hint must not outlive it.
  // (An observer, not AppLifecycleListener: hosts may skip lifecycle states.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hide(instant: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TooltipVisibility.of(context);
    if (!_visible) _hide(instant: true);
    if (!InteractionScope.of(context).animates && _anim.isAnimating) {
      _anim.value = _anim.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(covariant SuiteTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.isEmpty) _hide(instant: true);
  }

  // Dependency changes can arrive during a build. Do not dirty the portal
  // then; a later show also invalidates a queued hide from an older exit.
  void _hidePortal() {
    if (!_portal.isShowing) return;
    final generation = _generation;
    void hide() {
      if (mounted && generation == _generation && _anim.value == 0) {
        _portal.hide();
        _reportShowing(false);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => hide());
    } else {
      hide();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unwatchInput();
    _unwatchEscape();
    _reportShowing(false);
    _wait?.cancel();
    _dismiss?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _requestShow({required bool keyboard}) {
    _wait?.cancel();
    _wait = null;
    _dismiss?.cancel();
    if (!_visible || widget.message.isEmpty) return;
    // Passive text/tag hints cannot own keyboard focus. Watch Escape only
    // during their wait/visible lifetime, without moving or trapping focus.
    _watchEscape();
    final browsing =
        DateTime.now().difference(_lastHidden) <
        const Duration(milliseconds: 400);
    if (keyboard || browsing) {
      _show(instant: keyboard);
    } else {
      _wait = Timer(
        Duration(
          milliseconds: (widget.waitDuration.inMilliseconds * timeDilation)
              .round(),
        ),
        () => _show(instant: false),
      );
    }
  }

  void _show({required bool instant}) {
    if (!mounted || !_visible || widget.message.isEmpty) return;
    if (ModalRoute.isCurrentOf(context) == false) {
      _hide(instant: true);
      return;
    }
    _watchEscape();
    _wait = null;
    _generation++;
    final data = InteractionScope.of(context);
    _instant = instant || !data.animates;
    _reportShowing(true);
    _portal.show();
    if (_instant) {
      _anim.value = 1;
    } else {
      _anim
        ..duration = data.suite == InteractionSuite.standard
            ? const Duration(milliseconds: 120)
            : const Duration(milliseconds: 180)
        ..forward();
    }
    setState(() {});
  }

  void _hide({bool instant = false}) {
    _unwatchEscape();
    _wait?.cancel();
    _wait = null;
    _dismiss?.cancel();
    _generation++;
    if (!_portal.isShowing) return;
    _lastHidden = DateTime.now();
    final data = InteractionScope.of(context);
    if (instant || _instant || !data.animates) {
      _anim.value = 0;
      _hidePortal();
    } else {
      _anim
        ..reverseDuration = const Duration(milliseconds: 90)
        ..reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    return Semantics(
      tooltip: widget.excludeFromSemantics || widget.message.isEmpty
          ? null
          : widget.message,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => _escape(event),
        onFocusChange: (has) {
          final keyboard =
              _keyInput &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional;
          _keyboardFocused = has && keyboard;
          if (has && keyboard) {
            _requestShow(keyboard: true);
          } else if (!has && !_hovered) {
            _hide();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            _hovered = true;
            _requestShow(keyboard: _keyboardFocused && _keyInput);
          },
          // Only a hint the keyboard is still driving outlives the pointer.
          onExit: (_) {
            _hovered = false;
            if (!_keyboardFocused || !_keyInput) _hide();
          },
          child: Listener(
            onPointerDown: (_) {
              _keyboardFocused = false;
              _hide();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              excludeFromSemantics: true,
              onLongPress: () => _show(instant: false),
              onLongPressEnd: (_) {
                _dismiss = Timer(
                  Duration(
                    milliseconds:
                        (widget.showDuration.inMilliseconds * timeDilation)
                            .round(),
                  ),
                  () => _hide(),
                );
              },
              child: OverlayPortal.overlayChildLayoutBuilder(
                controller: _portal,
                overlayChildBuilder: (overlayContext, info) => _Bubble(
                  anchor: MatrixUtils.transformRect(
                    info.childPaintTransform,
                    Offset.zero & info.childSize,
                  ),
                  overlaySize: info.overlaySize,
                  message: widget.message,
                  animation: _anim,
                  data: data,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.anchor,
    required this.overlaySize,
    required this.message,
    required this.animation,
    required this.data,
  });

  final Rect anchor;
  final Size overlaySize;
  final String message;
  final Animation<double> animation;
  final InteractionData data;

  @override
  Widget build(BuildContext context) {
    final rect = anchor;
    // Below the anchor; flip above when there is no room.
    final below = rect.bottom + 40 < overlaySize.height;
    final p = data.palette;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF22313B) : const Color(0xFF26343D),
        borderRadius: suiteRadius(data.suite, 5),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFFEFF5F8),
          height: 1.3,
        ),
      ),
    );
    return SizedBox.expand(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: CustomSingleChildLayout(
            delegate: _BubbleLayout(rect, below),
            child: AnimatedBuilder(
              animation: animation,
              child: bubble,
              builder: (context, child) {
                final v = animation.value;
                final c = SuiteMotion.curve.transform(v);
                final dir = below ? 1.0 : -1.0;
                final marks = CustomPaint(
                  foregroundPainter: _BubbleMarks(data, c),
                  child: child,
                );
                return switch (data.suite) {
                  InteractionSuite.rail => Opacity(
                    opacity: c,
                    child: Transform.translate(
                      offset: Offset(0, -4 * dir * (1 - c)),
                      child: marks,
                    ),
                  ),
                  InteractionSuite.glow => Opacity(
                    opacity: c,
                    child: Transform.scale(
                      scale: 0.97 + 0.03 * c,
                      child: marks,
                    ),
                  ),
                  _ => Opacity(opacity: c, child: marks),
                };
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Centres the bubble on the anchor, then keeps it at least [_inset] inside
/// the window on every side (long text, narrow windows, anchors at the edge
/// or a collapsed icon rail), still next to its anchor.
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout(this.anchor, this.below);
  final Rect anchor;
  final bool below;
  static const _inset = 8.0;
  static const _gap = 6.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          (constraints.maxWidth - 2 * _inset).clamp(0, double.infinity),
          (constraints.maxHeight - 2 * _inset).clamp(0, double.infinity),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (anchor.center.dx - child.width / 2).clamp(
      _inset,
      (size.width - _inset - child.width).clamp(_inset, double.infinity),
    );
    final y = below ? anchor.bottom + _gap : anchor.top - _gap - child.height;
    return Offset(
      x,
      y.clamp(
        _inset,
        (size.height - _inset - child.height).clamp(_inset, double.infinity),
      ),
    );
  }

  @override
  bool shouldRelayout(_BubbleLayout old) =>
      old.anchor != anchor || old.below != below;
}

class _BubbleMarks extends CustomPainter {
  _BubbleMarks(this.data, this.t);
  final InteractionData data;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * t, 1.5),
          Paint()..color = p.isDark ? p.edge() : const Color(0xFF87CEFF),
        );
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.inflate(3 * (1 - t) + 2),
          color: (p.isDark ? p.edge() : const Color(0xFF87CEFF)).withValues(
            alpha: t,
          ),
          length: 5,
          width: 1.5,
        );
      case InteractionSuite.glow:
        paintGlowStrokes(
          canvas,
          RRect.fromRectXY(rect, 5, 5),
          p.isDark ? p.edge() : p.accent,
          0.35 * t,
        );
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_BubbleMarks old) => old.t != t || old.data != data;
}
