import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';
import 'surface_transition.dart';

/// A click-opened panel with interactive content (a member card with
/// "发消息 / 邀请", a quick editor). Unlike [SuiteTooltip] it never opens on
/// hover and it takes focus.
///
/// Opening moves focus into the panel; Tab stays inside it; Esc closes at
/// once and gives focus back to the anchor; outside taps close it (and
/// still reach their target). The panel flips above the anchor when there is
/// no room below and stays inside the window horizontally. Content that
/// changes size (loading → loaded → error) resizes smoothly, or at once
/// under reduced motion. Pointer opening uses the suite's menu entrance;
/// keyboard opening is instant.
///
/// The panel's side is picked by the room above and below the anchor, and
/// its size stays at least 8 px inside the window; long content scrolls
/// (focus traversal scrolls to each control). While the panel is leaving it
/// still shows but takes no taps, focus or screen-reader actions; reopening
/// turns the exit around and makes it usable again.
///
/// The content's `close` takes the source of the action that closes it
/// (pass the [InteractionSource] from `onActivate`). Called without one, it
/// uses what actually triggered the action: a pointer press or release
/// inside the panel plays the exit; anything else (keys, screen reader)
/// closes at once.
class SuitePopover extends StatefulWidget {
  const SuitePopover({
    required this.anchorBuilder,
    required this.contentBuilder,
    this.width = 260,
    this.semanticLabel,
    this.onOpenChanged,
    super.key,
  });

  /// The anchor's content; [open] tells whether the panel is showing.
  final Widget Function(BuildContext context, bool open) anchorBuilder;

  /// The panel's content. Call `close` from inside (e.g. after an action),
  /// passing the action's source.
  final Widget Function(
    BuildContext context,
    void Function([InteractionSource? source]) close,
  )
  contentBuilder;
  final double width;
  final String? semanticLabel;

  /// Reports opening and closing (e.g. to start loading the content).
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<SuitePopover> createState() => SuitePopoverState();
}

class SuitePopoverState extends State<SuitePopover>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchorFocus = FocusNode(debugLabel: 'popover-anchor');
  final _scope = FocusScopeNode(debugLabel: 'popover');
  late final _anim = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed && _portal.isShowing) {
        _portal.hide();
        if (mounted) setState(() {});
      }
    });

  bool get isOpen =>
      _portal.isShowing && _anim.status != AnimationStatus.reverse;

  /// Leaving: still painted, no longer interactive.
  bool get _closing =>
      _portal.isShowing && _anim.status == AnimationStatus.reverse;

  /// True only during the dispatch of a pointer press/release inside the
  /// panel, i.e. while a tap there runs its callbacks.
  bool _viaPointer = false;

  void _pointerEvent(PointerEvent _) {
    _viaPointer = true;
    scheduleMicrotask(() => _viaPointer = false);
  }

  void _closeFrom([InteractionSource? source]) => close(
    source:
        source ??
        (_viaPointer ? InteractionSource.pointer : InteractionSource.keyboard),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _anim.isAnimating) {
      _anim.value = _anim.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _anchorFocus.dispose();
    _scope.dispose();
    super.dispose();
  }

  void open({InteractionSource source = InteractionSource.pointer}) {
    if (isOpen) return;
    final data = InteractionScope.of(context);
    final d = surfaceDurations(data, SurfaceKind.menu);
    _anim
      ..duration = d.enter
      ..reverseDuration = d.exit;
    _portal.show();
    setState(() {});
    if (source == InteractionSource.keyboard || !data.animates) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
    widget.onOpenChanged?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_portal.isShowing) return;
      // Into the panel: its first focusable control, else the panel itself.
      final first = _scope.traversalDescendants
          .where((n) => n.canRequestFocus && !n.skipTraversal)
          .firstOrNull;
      (first ?? _scope).requestFocus();
    });
  }

  void close({InteractionSource source = InteractionSource.pointer}) {
    if (!_portal.isShowing || _anim.status == AnimationStatus.reverse) return;
    final instant =
        source == InteractionSource.keyboard ||
        !InteractionScope.of(context).animates;
    final hadFocus = _scope.hasFocus;
    if (instant) {
      _anim.value = 0;
      if (_portal.isShowing) _portal.hide();
      setState(() {});
    } else {
      _anim.reverse();
      setState(() {});
    }
    // Focus returns to the anchor only if it was inside the panel; an
    // outside click keeps focus where the user clicked.
    if (hadFocus || source == InteractionSource.keyboard) {
      _anchorFocus.requestFocus();
    }
    widget.onOpenChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) => _Placed(
        link: _link,
        anchor: context,
        width: widget.width,
        builder: (above, width, maxHeight) {
          final align = above ? Alignment.bottomCenter : Alignment.topCenter;
          final closing = _closing;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  close(source: InteractionSource.keyboard),
            },
            child: TapRegion(
              groupId: _link,
              onTapOutside: (_) => close(),
              child: SuiteSurfaceTransition(
                animation: _anim,
                kind: SurfaceKind.menu,
                alignment: align,
                radius: 8,
                child: IgnorePointer(
                  ignoring: closing,
                  child: ExcludeSemantics(
                    excluding: closing,
                    child: Semantics(
                      scopesRoute: true,
                      explicitChildNodes: true,
                      namesRoute: true,
                      label: widget.semanticLabel,
                      child: ExcludeFocus(
                        excluding: closing,
                        child: FocusScope(
                          node: _scope,
                          child: FocusTraversalGroup(
                            child: Listener(
                              onPointerDown: _pointerEvent,
                              onPointerUp: _pointerEvent,
                              child: _panel(data, p, above, width, maxHeight),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _link,
          child: SuitePressable(
            kind: PressableKind.icon,
            focusNode: _anchorFocus,
            selected: isOpen,
            minHeight: 30,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            semanticLabel: widget.semanticLabel,
            onActivate: (s) => isOpen ? close(source: s) : open(source: s),
            builder: (context, v) => widget.anchorBuilder(context, isOpen),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    InteractionData data,
    InteractionPalette p,
    bool above,
    double width,
    double maxHeight,
  ) {
    return CustomPaint(
      foregroundPainter: _PanelMark(data, above),
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: suiteRadius(data.suite, 8),
          border: Border.all(color: p.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: AnimatedSize(
            duration: data.sizeDuration(const Duration(milliseconds: 180)),
            curve: SuiteMotion.curve,
            alignment: Alignment.topCenter,
            child: Builder(
              builder: (context) => widget.contentBuilder(context, _closeFrom),
            ),
          ),
        ),
      ),
    );
  }
}

/// Positions the panel under (or above) the anchor, clamped to the window.
class _Placed extends StatelessWidget {
  const _Placed({
    required this.link,
    required this.anchor,
    required this.width,
    required this.builder,
  });

  final LayerLink link;
  final BuildContext anchor;
  final double width;
  final Widget Function(bool above, double width, double maxHeight) builder;

  @override
  Widget build(BuildContext context) {
    final box = anchor.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    if (box == null || !box.attached || !box.hasSize) {
      return const SizedBox.shrink();
    }
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    const inset = 8.0, gap = 6.0;
    final below = screen.height - rect.bottom - gap - inset;
    final over = rect.top - gap - inset;
    // Below when it has a comfortable height, else the roomier side.
    final above = below < 220 && over > below;
    final maxHeight = math.max(0.0, above ? over : below);
    final width = math.min(this.width, screen.width - 2 * inset);
    var dx = rect.width / 2 - width / 2;
    final left = rect.left + dx;
    if (left < inset) dx += inset - left;
    if (left + width > screen.width - inset) {
      dx -= left + width - (screen.width - inset);
    }
    return CompositedTransformFollower(
      link: link,
      targetAnchor: above ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: above ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(dx, above ? -gap : gap),
      child: Align(
        alignment: above ? Alignment.bottomLeft : Alignment.topLeft,
        child: builder(above, width, maxHeight),
      ),
    );
  }
}

/// Static suite mark on the panel edge facing the anchor.
class _PanelMark extends CustomPainter {
  _PanelMark(this.data, this.above);
  final InteractionData data;
  final bool above;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    switch (data.suite) {
      case InteractionSuite.rail:
        paintEdgeLine(
          canvas,
          rect.deflate(1),
          p.edge(0.9),
          top: !above,
          height: 1.5,
        );
      case InteractionSuite.scan:
        paintBrackets(canvas, rect.deflate(3), color: p.edge(0.7), length: 7);
      case InteractionSuite.glow:
        final band = Rect.fromLTWH(
          0,
          above ? size.height - 24 : 0,
          size.width,
          24,
        );
        canvas.save();
        canvas.clipRRect(suiteRadius(data.suite, 8).toRRect(rect));
        canvas.drawRect(
          band,
          Paint()
            ..shader = LinearGradient(
              begin: above ? Alignment.bottomCenter : Alignment.topCenter,
              end: above ? Alignment.topCenter : Alignment.bottomCenter,
              colors: [p.light(0.16), p.light(0)],
            ).createShader(band),
        );
        canvas.restore();
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_PanelMark old) => old.data != data || old.above != above;
}
