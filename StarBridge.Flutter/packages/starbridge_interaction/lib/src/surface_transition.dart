import 'package:flutter/foundation.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

enum SurfaceKind { menu, dialog, toast }

/// Entrance and exit durations for a floating surface in the current suite.
({Duration enter, Duration exit}) surfaceDurations(
  InteractionData data,
  SurfaceKind kind,
) {
  if (!data.animates) return (enter: Duration.zero, exit: Duration.zero);
  const ms = Duration.new;
  return switch ((data.suite, kind)) {
    (InteractionSuite.standard, SurfaceKind.dialog) => (
      enter: ms(milliseconds: 220),
      exit: ms(milliseconds: 140),
    ),
    (InteractionSuite.standard, _) => (
      enter: ms(milliseconds: 150),
      exit: ms(milliseconds: 100),
    ),
    (InteractionSuite.rail, _) => (
      enter: ms(milliseconds: 260),
      exit: ms(milliseconds: 140),
    ),
    (InteractionSuite.scan, SurfaceKind.dialog) => (
      enter: ms(milliseconds: 400),
      exit: ms(milliseconds: 200),
    ),
    (InteractionSuite.scan, _) => (
      enter: ms(milliseconds: 320),
      exit: ms(milliseconds: 180),
    ),
    (InteractionSuite.glow, SurfaceKind.dialog) => (
      enter: ms(milliseconds: 320),
      exit: ms(milliseconds: 130),
    ),
    (InteractionSuite.glow, _) => (
      enter: ms(milliseconds: 260),
      exit: ms(milliseconds: 130),
    ),
  };
}

double _iv(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

/// Animates a menu, dialog or toast in and out. Drive [animation] forward to
/// open and in reverse to close; reopening mid-close continues forward from
/// the current value, so a stale exit can never hide the new surface.
///
/// The child stays laid out at full size throughout; reveals use clips and
/// transforms only, never per-frame relayout. The child also stays mounted
/// across the change from "entering" to "settled" (different wrappers), so
/// focus and state inside it survive the end of the entrance.
class SuiteSurfaceTransition extends StatefulWidget {
  const SuiteSurfaceTransition({
    required this.animation,
    required this.kind,
    required this.child,
    this.alignment = Alignment.topLeft,
    this.radius = 9,
    this.tone,
    this.surfaceBounds,
    this.surfaceAlignment = Alignment.center,
    this.toastFromLeft = false,
    super.key,
  });

  final Animation<double> animation;
  final SurfaceKind kind;
  final Widget child;

  /// Origin for scale-based entrances (the anchor side for menus).
  final Alignment alignment;
  final double radius;

  /// Accent for toasts (success, danger…). Defaults to the palette accent.
  final Color? tone;

  /// Optional painted surface inside a larger layout canvas, such as a
  /// Material Dialog with viewport-sized inset/alignment wrappers.
  /// Coordinates are local to the untransformed child; layout stays intact.
  final Rect? surfaceBounds;
  final Alignment surfaceAlignment;

  /// Rail toast travel follows its screen edge. Existing callers retain the
  /// right-edge default; placement and timer ownership remain with the host.
  final bool toastFromLeft;

  @override
  State<SuiteSurfaceTransition> createState() => _SuiteSurfaceTransitionState();
}

class _SuiteSurfaceTransitionState extends State<SuiteSurfaceTransition> {
  /// Keeps the child's element when the wrappers around it change.
  final _keep = GlobalKey(debugLabel: 'surface-child');

  Animation<double> get animation => widget.animation;
  SurfaceKind get kind => widget.kind;
  Alignment get alignment => widget.alignment;
  double get radius => widget.radius;
  Color? get tone => widget.tone;
  Rect _surface(Size size) => widget.surfaceBounds ?? (Offset.zero & size);

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final boundary = RepaintBoundary(key: _keep, child: widget.child);
    return AnimatedBuilder(
      animation: animation,
      child: boundary,
      builder: (context, child) {
        final t = animation.value;
        final exiting =
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        if (!data.animates) {
          // No motion: the final static form, or nothing once closing.
          return exiting ? const SizedBox.shrink() : _settled(data, child!);
        }
        if (t >= 1 && animation.status == AnimationStatus.completed) {
          return _settled(data, child!);
        }
        return exiting ? _exit(data, t, child!) : _enter(data, t, child!);
      },
    );
  }

  Color _tone(InteractionPalette p) => tone ?? p.accent;

  /// A menu stays as wide as its field while it moves.
  Matrix4 _glowScale(double scale) => Matrix4.diagonal3Values(
    kind == SurfaceKind.menu ? 1 : scale,
    scale,
    1,
  );

  /// Final static form: plain child plus the suite's resting marks.
  Widget _settled(InteractionData data, Widget child) =>
      _decorate(data, child, rail: 1, brackets: 1, glow: 1);

  Widget _decorate(
    InteractionData data,
    Widget child, {
    double rail = 0,
    double brackets = 0,
    double glow = 0,
  }) {
    if (widget.surfaceBounds?.isEmpty ?? false) return child;
    final p = data.palette;
    final r = suiteRadius(data.suite, radius);
    switch (data.suite) {
      case InteractionSuite.rail:
        return CustomPaint(
          foregroundPainter: _MarkPainter((canvas, size) {
            final rect = _surface(size);
            switch (kind) {
              case SurfaceKind.menu:
                canvas.save();
                canvas.clipRRect(r.toRRect(rect));
                canvas.drawRect(
                  Rect.fromLTWH(0, 0, 2, size.height * rail),
                  Paint()..color = p.edge(),
                );
                canvas.restore();
              case SurfaceKind.dialog:
                canvas.save();
                canvas.clipRRect(r.toRRect(rect));
                paintEdgeLine(canvas, rect, p.edge(), scale: rail, top: true);
                canvas.restore();
              case SurfaceKind.toast:
                canvas.save();
                canvas.clipRRect(r.toRRect(rect));
                final h = rect.height * rail;
                canvas.drawRect(
                  Rect.fromLTWH(
                    rect.left,
                    rect.top + (rect.height - h) / 2,
                    3,
                    h,
                  ),
                  Paint()..color = _tone(p),
                );
                canvas.restore();
            }
          }),
          child: child,
        );
      case InteractionSuite.scan:
        return CustomPaint(
          foregroundPainter: _MarkPainter((canvas, size) {
            final rect = _surface(size);
            paintBrackets(
              canvas,
              kind == SurfaceKind.dialog ? rect.inflate(4) : rect.deflate(2),
              color: (kind == SurfaceKind.toast ? _tone(p) : p.edge())
                  .withValues(alpha: brackets),
              length: kind == SurfaceKind.dialog ? 10 : 7,
            );
          }),
          child: child,
        );
      case InteractionSuite.glow:
        if (!p.isDark && glow <= 0) return child;
        return CustomPaint(
          painter: _MarkPainter((canvas, size) {
            final rrect = r.toRRect(_surface(size));
            final base = kind == SurfaceKind.toast ? _tone(p) : p.accent;
            paintGlowStrokes(
              canvas,
              rrect,
              base,
              (p.isDark ? 0.35 : 0.2) * glow,
            );
          }),
          child: child,
        );
      case InteractionSuite.standard:
        return child;
    }
  }

  Widget _enter(InteractionData data, double t, Widget child) {
    final c = SuiteMotion.curve.transform(t);
    switch (data.suite) {
      case InteractionSuite.standard:
        return Opacity(
          opacity: t,
          child: kind == SurfaceKind.dialog
              ? Transform.scale(
                  alignment: widget.surfaceAlignment,
                  scale: 0.96 + 0.04 * c,
                  child: child,
                )
              : child,
        );
      case InteractionSuite.rail:
        switch (kind) {
          case SurfaceKind.menu:
            return ClipRect(
              clipper: _RevealClipper(top: 0, fraction: c),
              child: Transform.translate(
                offset: Offset(-6 * (1 - c), 0),
                child: _decorate(data, child, rail: c),
              ),
            );
          case SurfaceKind.dialog:
            return Opacity(
              opacity: c,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - c)),
                child: _decorate(data, child, rail: _iv(t, 0.3, 1)),
              ),
            );
          case SurfaceKind.toast:
            return Opacity(
              opacity: c,
              child: Transform.translate(
                offset: Offset((widget.toastFromLeft ? -30 : 30) * (1 - c), 0),
                child: _decorate(data, child, rail: _iv(t, 0.4, 1)),
              ),
            );
        }
      case InteractionSuite.scan:
        if (kind == SurfaceKind.menu) {
          return Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              ClipRect(
                clipper: _RevealClipper(top: 0, fraction: c),
                child: _decorate(data, child, brackets: _iv(t, 0.6, 1)),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MarkPainter((canvas, size) {
                      if (t >= 1) return;
                      final y = size.height * c;
                      canvas.drawRect(
                        Rect.fromLTWH(0, y - 1, size.width, 2),
                        Paint()..color = data.palette.edge(),
                      );
                    }),
                  ),
                ),
              ),
            ],
          );
        }
        // Dialog and toast: a line forms, then opens into the surface.
        const split = 0.45;
        final lineT = SuiteMotion.curve.transform(_iv(t, 0, split));
        final openT = SuiteMotion.curve.transform(_iv(t, split, 1));
        final color = kind == SurfaceKind.toast
            ? _tone(data.palette)
            : data.palette.edge();
        return Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            // Always laid out so the surface keeps its size; a zero-height
            // band simply paints nothing during the line phase.
            ClipRect(
              clipper: _BandClipper(openT, bounds: widget.surfaceBounds),
              child: _decorate(data, child, brackets: _iv(t, 0.75, 1)),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MarkPainter((canvas, size) {
                    if (openT >= 1) return;
                    final rect = _surface(size);
                    final w = rect.width * lineT;
                    final h = math.max(2.0, rect.height * openT);
                    canvas.drawRect(
                      Rect.fromCenter(center: rect.center, width: w, height: 2),
                      Paint()..color = color,
                    );
                    if (openT > 0) {
                      final band = Rect.fromCenter(
                        center: rect.center,
                        width: rect.width,
                        height: h,
                      );
                      final edge = Paint()
                        ..color = color.withValues(alpha: 0.9 * (1 - openT));
                      canvas.drawRect(
                        Rect.fromLTWH(band.left, band.top, band.width, 1.5),
                        edge,
                      );
                      canvas.drawRect(
                        Rect.fromLTWH(
                          band.left,
                          band.bottom - 1.5,
                          band.width,
                          1.5,
                        ),
                        edge,
                      );
                    }
                  }),
                ),
              ),
            ),
          ],
        );
      case InteractionSuite.glow:
        final (from, opacityEnd) = switch (kind) {
          SurfaceKind.dialog => (0.9, 0.6),
          _ => (0.94, 1.0),
        };
        final bloom = kind == SurfaceKind.dialog
            ? (t < 0.6 ? t / 0.6 * 2.2 : 2.2 - (t - 0.6) / 0.4 * 1.2)
            : c;
        return Opacity(
          opacity: _iv(t, 0, opacityEnd),
          child: Transform(
            alignment: kind == SurfaceKind.dialog
                ? widget.surfaceAlignment
                : alignment,
            transform: _glowScale(from + (1 - from) * c),
            child: _decorate(data, child, glow: bloom),
          ),
        );
    }
  }

  Widget _exit(InteractionData data, double t, Widget child) {
    final c = SuiteMotion.exitCurve.transform(1 - t);
    switch (data.suite) {
      case InteractionSuite.standard:
        return Opacity(opacity: t, child: child);
      case InteractionSuite.rail:
        if (kind == SurfaceKind.menu) {
          return ClipRect(
            clipper: _RevealClipper(top: 0, fraction: 1 - c),
            child: _decorate(data, child, rail: 1),
          );
        }
        final offset = kind == SurfaceKind.toast
            ? Offset((widget.toastFromLeft ? -30 : 30) * c, 0)
            : Offset(0, 8 * c);
        return Opacity(
          opacity: 1 - c,
          child: Transform.translate(
            offset: offset,
            child: _decorate(data, child, rail: 1),
          ),
        );
      case InteractionSuite.scan:
        // Collapse to a centre line, then the line shrinks away.
        final collapse = _iv(c, 0, 0.55);
        final shrink = _iv(c, 0.55, 1);
        return Opacity(
          opacity: 1 - shrink,
          child: Transform(
            alignment: kind == SurfaceKind.dialog
                ? widget.surfaceAlignment
                : Alignment.center,
            transform: Matrix4.diagonal3Values(1 - shrink, 1, 1),
            child: ClipRect(
              clipper: _BandClipper(
                math.max(0.02, 1 - collapse),
                bounds: widget.surfaceBounds,
              ),
              child: _decorate(data, child, brackets: 1 - collapse),
            ),
          ),
        );
      case InteractionSuite.glow:
        return Opacity(
          opacity: 1 - c,
          child: Transform(
            alignment: kind == SurfaceKind.dialog
                ? widget.surfaceAlignment
                : alignment,
            transform: _glowScale(1 - 0.04 * c),
            child: _decorate(data, child, glow: 1 - c),
          ),
        );
    }
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.draw);
  final void Function(Canvas, Size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  // Decoration is not a pointer target. A host may paint its dialog inside
  // viewport-sized inset/alignment wrappers; the background glow must not
  // turn all that empty space into a target and block the modal barrier.
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_MarkPainter old) => true;
}

/// Reveals from the top edge downward.
class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper({required this.top, required this.fraction});
  final double top;
  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    -20,
    top - 20,
    size.width + 40,
    size.height * fraction + 20,
  );

  @override
  bool shouldReclip(_RevealClipper old) => old.fraction != fraction;
}

/// A horizontal band centred vertically, [fraction] of the full height.
class _BandClipper extends CustomClipper<Rect> {
  _BandClipper(this.fraction, {this.bounds});
  final double fraction;
  final Rect? bounds;

  @override
  Rect getClip(Size size) {
    final rect = bounds ?? (Offset.zero & size);
    final h = rect.height * fraction;
    return Rect.fromLTWH(
      rect.left - 20,
      rect.center.dy - h / 2,
      rect.width + 40,
      h,
    );
  }

  @override
  bool shouldReclip(_BandClipper old) =>
      old.fraction != fraction || old.bounds != bounds;
}

/// Modal dialog route using the suite's dialog transition.
///
/// The route follows a live [InteractionScope] so a suite, palette or
/// reduced-motion change reaches an open dialog: the opener's scope via
/// [link] (what [showSuiteDialog] passes), otherwise a scope above the
/// navigator. [data] is only the last fallback. [instant] (keyboard-opened)
/// skips the entrance.
class SuiteDialogRoute<T> extends PopupRoute<T> {
  SuiteDialogRoute({
    required this.builder,
    required this.data,
    this.link,
    this.instant = false,
    this.surfaceBuilder,
    this.barrierLabel = 'Dismiss',
    super.settings,
    super.requestFocus,
    super.traversalEdgeBehavior,
  }) : _latest = data;

  final WidgetBuilder builder;
  final InteractionData data;

  /// The opener's live scope ([InteractionScope.linkOf]).
  final ValueListenable<InteractionData>? link;
  final bool instant;

  /// Optional host geometry adapter. The route still owns live settings,
  /// controller, modal barrier, focus and navigation lifecycle.
  final Widget Function(BuildContext, Animation<double>, Widget)?
  surfaceBuilder;
  InteractionData _latest;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => _latest.palette.isDark
      ? const Color(0xA6000000)
      : const Color(0x66000000);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => instant
      ? Duration.zero
      : surfaceDurations(_latest, SurfaceKind.dialog).enter;

  @override
  Duration get reverseTransitionDuration =>
      surfaceDurations(_latest, SurfaceKind.dialog).exit;

  Widget _scoped(BuildContext context, Widget child) {
    final tracked = Builder(
      builder: (context) {
        _track(InteractionScope.of(context));
        return child;
      },
    );
    final link = this.link;
    if (link != null) return InteractionScope.follow(link, child: tracked);
    if (InteractionScope.maybeOf(context) != null) return tracked;
    return InteractionScope(data: data, child: tracked);
  }

  void _track(InteractionData live) {
    _latest = live;
    if (!live.animates) _settleController();
  }

  /// The scrim follows the same live settings as the dialog itself, in the
  /// same frame: it reads them where it is built instead of waiting for a
  /// route-level refresh one frame after the content changed.
  @override
  Widget buildModalBarrier() {
    final barrier = Builder(
      builder: (context) {
        _latest = InteractionScope.maybeOf(context) ?? _latest;
        // Reduced motion: the scrim is simply there, at full strength, from
        // the build that learns about it — not after the route's controller
        // has been settled (which can only happen after this frame).
        if (!_latest.animates &&
            controller?.status != AnimationStatus.reverse &&
            controller?.status != AnimationStatus.dismissed) {
          return ModalBarrier(
            color: barrierColor,
            dismissible: barrierDismissible,
            semanticsLabel: barrierLabel,
            barrierSemanticsDismissible: semanticsDismissible,
          );
        }
        return super.buildModalBarrier();
      },
    );
    final link = this.link;
    if (link != null) return InteractionScope.follow(link, child: barrier);
    return barrier;
  }

  /// Reduced motion turned on while the route is moving: finish the route's
  /// own controller too (entering → completed, leaving → dismissed), not
  /// just the painted frame. Deferred to after the frame because this runs
  /// during build; pop futures, barrier and focus follow the normal route
  /// lifecycle.
  void _settleController() {
    final c = controller;
    if (c == null || !c.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.isAnimating) return;
      c.value = c.status == AnimationStatus.reverse ? 0 : 1;
    });
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> b,
  ) => _scoped(context, Builder(builder: builder));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _scoped(
    context,
    Center(
      child:
          surfaceBuilder?.call(context, animation, child) ??
          SuiteSurfaceTransition(
            animation: animation,
            kind: SurfaceKind.dialog,
            child: child,
          ),
    ),
  );
}

/// Shows [builder] as a dialog with the current suite's transition. Pass
/// [source] = keyboard when a key opened it; the dialog then appears at once.
Future<T?> showSuiteDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  InteractionSource source = InteractionSource.pointer,
}) {
  final data = InteractionScope.of(context);
  return Navigator.of(context).push(
    SuiteDialogRoute<T>(
      builder: builder,
      data: data,
      link: InteractionScope.linkOf(context),
      instant: source == InteractionSource.keyboard,
    ),
  );
}

@immutable
class SuiteMenuEntry {
  const SuiteMenuEntry(this.label, {this.enabled = true});
  final String label;
  final bool enabled;
}

/// Anchor button plus dropdown menu. Esc, outside clicks and arrow keys work;
/// keyboard opening shows the menu immediately.
class SuiteDropdown extends StatefulWidget {
  const SuiteDropdown({
    required this.label,
    required this.entries,
    required this.onSelected,
    this.menuWidth = 180,
    super.key,
  });

  final String label;
  final List<SuiteMenuEntry> entries;
  final ValueChanged<int> onSelected;
  final double menuWidth;

  @override
  State<SuiteDropdown> createState() => SuiteDropdownState();
}

class SuiteDropdownState extends State<SuiteDropdown>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final _anim = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed) _portal.hide();
    });
  final _itemFocus = <FocusNode>[];
  final _anchorFocus = FocusNode(debugLabel: 'dropdown-anchor');

  bool get isOpen =>
      _portal.isShowing && _anim.status != AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(SuiteDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes();
  }

  /// One focus node per current entry. Entries may grow, shrink or be
  /// replaced while open; a focused entry that disappears hands focus to
  /// the nearest remaining one (or the anchor when the list is empty).
  void _syncFocusNodes() {
    final n = widget.entries.length;
    var lostFocus = false;
    while (_itemFocus.length > n) {
      final node = _itemFocus.removeLast();
      lostFocus |= node.hasFocus;
      // Dispose after this frame: the old entry may still be mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
    }
    while (_itemFocus.length < n) {
      _itemFocus.add(
        FocusNode(debugLabel: 'dropdown-item-${_itemFocus.length}'),
      );
    }
    if (lostFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (_itemFocus.isNotEmpty ? _itemFocus.last : _anchorFocus).requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-transition: jump to the end state.
    if (!InteractionScope.of(context).animates && _anim.isAnimating) {
      _anim.value = _anim.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    for (final f in _itemFocus) {
      f.dispose();
    }
    _anchorFocus.dispose();
    super.dispose();
  }

  void open({InteractionSource source = InteractionSource.pointer}) {
    final data = InteractionScope.of(context);
    final d = surfaceDurations(data, SurfaceKind.menu);
    _anim
      ..duration = d.enter
      ..reverseDuration = d.exit;
    _portal.show();
    if (source == InteractionSource.keyboard || !data.animates) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
    if (source == InteractionSource.keyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _itemFocus.isNotEmpty) _itemFocus.first.requestFocus();
      });
    }
  }

  /// Closes the menu. Keyboard closing (Esc, Enter on an entry) removes it at
  /// once and returns focus to the anchor; pointer closing plays the exit.
  void close({InteractionSource source = InteractionSource.pointer}) {
    if (!_portal.isShowing) return;
    final keyboard = source == InteractionSource.keyboard;
    if (keyboard || !InteractionScope.of(context).animates) {
      _anim.value = 0;
      if (_portal.isShowing) _portal.hide();
    } else {
      _anim.reverse();
    }
    if (keyboard) _anchorFocus.requestFocus();
  }

  void toggle(InteractionSource source) =>
      isOpen ? close(source: source) : open(source: source);

  /// Focus node of entry [i] (lab demos use it to locate the entry).
  FocusNode itemFocus(int i) => _itemFocus[i];

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Stack(
        children: [
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: InteractionScope(
                data: data,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        close(source: InteractionSource.keyboard),
                  },
                  child: FocusTraversalGroup(
                    child: TapRegion(
                      groupId: _link,
                      onTapOutside: (_) => close(),
                      child: SuiteSurfaceTransition(
                        animation: _anim,
                        kind: SurfaceKind.menu,
                        radius: 7,
                        child: Container(
                          width: widget.menuWidth,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: p.raised,
                            borderRadius: suiteRadius(data.suite, 7),
                            border: Border.all(color: p.border),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < widget.entries.length; i++)
                                SuitePressable(
                                  kind: PressableKind.menuItem,
                                  focusNode: _itemFocus[i],
                                  baseRadius: 4,
                                  minHeight: 30,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  onActivate: widget.entries[i].enabled
                                      ? (source) {
                                          widget.onSelected(i);
                                          close(source: source);
                                        }
                                      : null,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(widget.entries[i].label),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // Outside taps close the menu but still reach what they hit, so no
      // invisible barrier swallows clicks meant for other controls.
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _link,
          child: SuitePressable(
            kind: PressableKind.secondary,
            focusNode: _anchorFocus,
            minHeight: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onActivate: toggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
