import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_page_motion.dart';

/// Opaque, maintained page route: navigation, guards and titles are not owned
/// here. This adapter owns live settings/controller and desktop page painting.
class StarBridgePageRoute<T> extends MaterialPageRoute<T>
    implements StarBridgeInitialReadOrigin {
  @override
  InteractionSource get initialReadSource =>
      instant ? InteractionSource.keyboard : InteractionSource.programmatic;
  StarBridgePageRoute.fromContext(
    BuildContext context, {
    required super.builder,
    super.settings,
    InteractionSource? source,
  }) : data = resolveStarBridgeInteraction(context),
       link = InteractionScope.linkOf(context),
       instant =
           (source ?? currentStarBridgeActivationSource) ==
           InteractionSource.keyboard,
       super(allowSnapshotting: false) {
    _latest = data;
  }
  final InteractionData data;
  final ValueListenable<InteractionData>? link;
  final bool instant;
  late InteractionData _latest;
  bool _instantExit = false,
      _disposed = false,
      _queued = false,
      _coveredByPage = false;
  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    _coveredByPage = nextRoute is PageRoute && nextRoute.opaque;
    super.didChangeNext(nextRoute);
    changedInternalState();
  }

  @override
  void didPopNext(Route<dynamic> nextRoute) {
    _coveredByPage = false;
    super.didPopNext(nextRoute);
    changedInternalState();
  }

  @override
  Duration get transitionDuration =>
      instant ? Duration.zero : starBridgePageDurations(_latest).enter;
  @override
  Duration get reverseTransitionDuration =>
      _instantExit ? Duration.zero : starBridgePageDurations(_latest).exit;
  void _track(InteractionData current) {
    final changed = _latest.suite != current.suite;
    _latest = current;
    final c = controller;
    if (c != null) {
      c.duration = transitionDuration;
      c.reverseDuration = reverseTransitionDuration;
    }
    if ((!current.animates || changed) && c?.isAnimating == true && !_queued) {
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (_disposed) return;
        final moving = controller;
        if (moving?.isAnimating == true) {
          moving!.value = moving.status == AnimationStatus.reverse ? 0 : 1;
        }
      });
    }
  }

  Widget _scoped(BuildContext context, Widget child) {
    final tracked = Builder(
      builder: (context) {
        _track(InteractionScope.of(context));
        return child;
      },
    );
    if (link != null) return InteractionScope.follow(link!, child: tracked);
    return InteractionScope(
      data: resolveStarBridgeInteraction(context),
      child: tracked,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      _scoped(context, super.buildPage(context, animation, secondaryAnimation));
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _scoped(
    context,
    StarBridgePageTransition(
      animation: animation,
      active: !_coveredByPage,
      instant: animation.status == AnimationStatus.reverse
          ? _instantExit
          : instant,
      child: child,
    ),
  );
  @override
  bool didPop(T? result) {
    _latest = link?.value ?? _latest;
    _instantExit =
        currentStarBridgeActivationSource == InteractionSource.keyboard;
    controller?.reverseDuration = reverseTransitionDuration;
    final popped = super.didPop(result);
    if (!popped) _instantExit = false;
    return popped;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Call only after the caller's leave guard and owner checks have succeeded.
/// Shell pages also guard system/Esc requests using PopScope; this avoids
/// confirming the same choice twice for a self-navigating page's own button.
Future<void> popStarBridgePageAfterGuard(BuildContext context) async {
  final route = ModalRoute.of(context);
  if (route is StarBridgePageRoute &&
      route.isCurrent &&
      !route.willHandlePopInternally) {
    Navigator.of(context).pop();
  } else {
    await Navigator.of(context).maybePop();
  }
}
