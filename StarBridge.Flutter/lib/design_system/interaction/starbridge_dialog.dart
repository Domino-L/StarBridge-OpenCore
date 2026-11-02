import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_dialog_surface.dart';
import 'starbridge_interaction_theme.dart';

/// Source-aware client route. Scope following and the tested scrim remain
/// owned by the approved package; keyboard exit adds no animation tail.
class StarBridgeDialogRoute<T> extends SuiteDialogRoute<T>
    implements StarBridgeInitialReadOrigin {
  @override
  InteractionSource get initialReadSource =>
      instant ? InteractionSource.keyboard : InteractionSource.programmatic;
  final _completeActivation = captureStarBridgeActivationCompletion();
  StarBridgeDialogRoute({
    required super.builder,
    required super.data,
    required super.barrierLabel,
    super.link,
    super.instant,
    super.requestFocus,
    super.traversalEdgeBehavior,
    this.dismissible = true,
    this.autofocusFallback = true,
  }) : super(surfaceBuilder: _surface);

  static Widget _surface(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) => StarBridgeDialogSurface(animation: animation, child: child);

  final bool dismissible;

  /// Keep the existing empty-dialog fallback by default. A dialog with its
  /// own autofocus target can let that target win instead of this ancestor.
  final bool autofocusFallback;
  @override
  bool get barrierDismissible => dismissible;

  void completeActivation(InteractionSource source) =>
      _completeActivation(source);

  void finishKeyboardExit() {
    if (navigator == null) {
      return; // A disposed route retains its old controller.
    }
    final animation = controller;
    if (animation != null && animation.status == AnimationStatus.reverse) {
      animation.value = 0;
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> b,
  ) => !barrierDismissible
      ? super.buildPage(context, a, b)
      : CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!barrierDismissible) return;
              navigator?.maybePop().then((popped) {
                if (popped) finishKeyboardExit();
              });
            },
          },
          child: Focus(
            autofocus: autofocusFallback,
            canRequestFocus: autofocusFallback,
            child: super.buildPage(context, a, b),
          ),
        );
}

Future<T?> showStarBridgeDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  InteractionSource? source,
  bool useRootNavigator = true,
  bool barrierDismissible = true,
  bool? requestFocus,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  ValueChanged<StarBridgeDialogRoute<T>>? onRouteCreated,
}) {
  final effectiveSource =
      source ?? StarBridgeActivationOrigin.sourceOf(context);
  final route = StarBridgeDialogRoute<T>(
    builder: builder,
    data:
        InteractionScope.maybeOf(context) ??
        resolveStarBridgeInteraction(context),
    link: InteractionScope.linkOf(context),
    instant: effectiveSource == InteractionSource.keyboard,
    dismissible: barrierDismissible,
    requestFocus: requestFocus,
    traversalEdgeBehavior: traversalEdgeBehavior,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  );
  onRouteCreated?.call(route);
  return Navigator.of(context, rootNavigator: useRootNavigator).push(route);
}

void dismissStarBridgeDialog<T>(
  BuildContext context, {
  InteractionSource source = InteractionSource.pointer,
  T? result,
}) {
  final route = ModalRoute.of(context);
  if (route is StarBridgeDialogRoute) route.completeActivation(source);
  Navigator.of(context).pop<T>(result);
  if (source == InteractionSource.keyboard && route is StarBridgeDialogRoute) {
    route.finishKeyboardExit();
  }
}

/// Retires only the route owned by an invalidated/disposed editor. Never pops
/// an unrelated top route; removing it yields no result to the old edit.
void retireStarBridgeDialog(
  StarBridgeDialogRoute<dynamic>? route, {
  bool includeClosing = false,
}) {
  if (route == null) return;
  void remove() {
    if (route.isActive) {
      route.navigator?.removeRoute(route);
    } else if (includeClosing) {
      route.finishKeyboardExit();
    }
  }

  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    WidgetsBinding.instance.addPostFrameCallback((_) => remove());
  } else {
    remove();
  }
}
