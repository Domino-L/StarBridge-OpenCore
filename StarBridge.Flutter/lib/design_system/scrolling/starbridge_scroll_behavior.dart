import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../tokens/starbridge_tokens.dart';
import 'wheel_direction_guard.dart';

/// One wheel policy for all Flutter windows. Controllers and their positions
/// remain owned by the feature (including chat history and read receipts).
class StarBridgeScrollBehavior extends MaterialScrollBehavior {
  const StarBridgeScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => _WheelSurface(details: details, child: child);
}

class _WheelSurface extends StatefulWidget {
  const _WheelSurface({required this.details, required this.child});
  final ScrollableDetails details;
  final Widget child;
  @override
  State<_WheelSurface> createState() => _WheelSurfaceState();
}

class _WheelSurfaceState extends State<_WheelSurface>
    with SingleTickerProviderStateMixin {
  final guard = WheelDirectionGuard();
  late final Ticker ticker = createTicker(_tick);
  ScrollPosition? position;
  double target = 0;
  double lastPixels = 0;
  Duration previous = Duration.zero;
  bool reduced = false;

  double delta(PointerScrollEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        HardwareKeyboard.instance.isShiftPressed) {
      return 0;
    }
    if (axisDirectionToAxis(widget.details.direction) != Axis.vertical) {
      return 0;
    }
    return axisDirectionIsReversed(widget.details.direction)
        ? -event.scrollDelta.dy
        : event.scrollDelta.dy;
  }

  ScrollPosition? get current {
    final controller = widget.details.controller;
    if (controller == null || controller.positions.length != 1) return null;
    final p = controller.position;
    return p.hasContentDimensions && p.physics.shouldAcceptUserOffset(p)
        ? p
        : null;
  }

  bool canHandle(PointerScrollEvent event) {
    final p = current, d = delta(event);
    return p != null &&
        d != 0 &&
        (p.pixels + d).clamp(p.minScrollExtent, p.maxScrollExtent) != p.pixels;
  }

  void wheel(PointerScrollEvent event) {
    final p = current;
    if (p == null) return;
    final d = delta(event);
    final boundary =
        p.pixels <= p.minScrollExtent || p.pixels >= p.maxScrollExtent;
    if (!guard.accept(
      d,
      event.timeStamp.inMilliseconds,
      moving: ticker.isActive,
      boundary: boundary,
    )) {
      stop();
      return;
    }
    if (position != p ||
        !ticker.isActive ||
        (target - p.pixels).sign != d.sign) {
      target = p.pixels;
    }
    position = p;
    lastPixels = p.pixels;
    final limit = math.max(104.0, p.viewportDimension * .75);
    target = (target + d)
        .clamp(p.pixels - limit, p.pixels + limit)
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    if (reduced) {
      p.pointerScroll(target - p.pixels);
      stop();
      return;
    }
    if (!ticker.isActive) {
      previous = Duration.zero;
      ticker.start();
    }
    event.respond(allowPlatformDefault: false);
  }

  void _tick(Duration elapsed) {
    final p = position;
    if (!mounted ||
        p == null ||
        current != p ||
        !TickerMode.valuesOf(context).enabled) {
      stop();
      return;
    }
    // History prepend/restoration, scrollbar and programmatic navigation win.
    if ((p.pixels - lastPixels).abs() > .01) {
      stop();
      guard.reset();
      return;
    }
    target = target.clamp(p.minScrollExtent, p.maxScrollExtent);
    final remaining = target - p.pixels;
    final dt = previous == Duration.zero
        ? 1 / 60
        : ((elapsed - previous).inMicroseconds / 1000000).clamp(0, .04);
    previous = elapsed;
    p.pointerScroll(
      remaining.abs() <= .3 ? remaining : remaining * (1 - math.exp(-18 * dt)),
    );
    lastPixels = p.pixels;
    if (remaining.abs() <= .3) stop();
  }

  void stop() {
    ticker.stop();
    position = null;
  }

  bool key(KeyEvent event) {
    stop();
    guard.reset();
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced =
        MediaQuery.disableAnimationsOf(context) ||
        context.tokens.motion.pointerMicro == Duration.zero;
    if (!TickerMode.valuesOf(context).enabled || reduced) stop();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(key);
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _WheelCapture(owner: this, child: widget.child);
}

class _WheelCapture extends SingleChildRenderObjectWidget {
  const _WheelCapture({required this.owner, required super.child});
  final _WheelSurfaceState owner;
  @override
  _WheelRender createRenderObject(BuildContext context) => _WheelRender(owner);
  @override
  void updateRenderObject(BuildContext context, _WheelRender renderObject) =>
      renderObject.surface = owner;
}

/// Capture only wheel signals before Scrollable registers its instant handler.
/// Resolve the deepest hit surface first so nested lists never scroll twice.
class _WheelRender extends RenderProxyBox {
  _WheelRender(this.surface);
  _WheelSurfaceState surface;
  List<_WheelRender> nested = const [];
  bool editable = false;
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    final start = result.path.length;
    hitTestChildren(result, position: position);
    final descendants = result.path.skip(start);
    nested = descendants
        .map((e) => e.target)
        .whereType<_WheelRender>()
        .toList();
    editable = descendants.any((e) => e.target is RenderEditable);
    return true;
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerScrollInertiaCancelEvent) {
      surface.stop();
      surface.guard.reset();
    }
    if (event is! PointerScrollEvent || editable) return;
    for (final region in [...nested.reversed, this]) {
      if (region.surface.canHandle(event)) {
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          (_) => region.surface.wheel(event),
        );
        return;
      }
    }
  }
}
