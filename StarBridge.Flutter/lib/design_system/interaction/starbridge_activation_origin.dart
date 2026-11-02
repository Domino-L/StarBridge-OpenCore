import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

/// Reads the current command source synchronously, even when an existing
/// callback opens a route before another build. It is not persisted state.
class StarBridgeActivationOrigin extends InheritedWidget {
  const StarBridgeActivationOrigin({
    required this.source,
    required super.child,
    super.key,
  });

  final ValueListenable<InteractionSource> source;

  static InteractionSource sourceOf(BuildContext context) {
    // An explicit command may use a context captured by a different target.
    // Its current source takes precedence; do not mutate that target's origin.
    final command = Zone.current[_activationCommandKey] as _ActivationCommand?;
    if (command?.active == true) return command!.source;
    return context
            .getInheritedWidgetOfExactType<StarBridgeActivationOrigin>()
            ?.source
            .value ??
        currentStarBridgeActivationSource;
  }

  @override
  bool updateShouldNotify(StarBridgeActivationOrigin oldWidget) =>
      source != oldWidget.source;
}

final _activationCommandKey = Object();

/// Routes publish the origin of automatic first reads without importing their
/// implementations into this module. This never owns navigation or a request.
abstract interface class StarBridgeInitialReadOrigin {
  InteractionSource get initialReadSource;
}

/// Read-only opening fact for an in-place viewport switch. It is not the live
/// source of child actions: an explicit action's source always takes priority.
Widget starBridgeInitialReadViewport(
  BuildContext context, {
  required InteractionSource source,
  required Widget child,
}) => _StarBridgeInitialReadScope(
  source: source,
  viewportRoute: ModalRoute.of(context),
  child: child,
);

class _StarBridgeInitialReadScope extends InheritedWidget {
  const _StarBridgeInitialReadScope({
    required this.source,
    required this.viewportRoute,
    required super.child,
  });
  final InteractionSource source;
  final ModalRoute<dynamic>? viewportRoute;
  @override
  bool updateShouldNotify(_StarBridgeInitialReadScope oldWidget) =>
      source != oldWidget.source || viewportRoute != oldWidget.viewportRoute;
}

/// For synchronous native event delegates: keep synchronous exceptions and
/// callback order unchanged. Awaited commands still use runStarBridgeActivation.
T runStarBridgeSynchronousActivation<T>(
  InteractionSource source,
  T Function() action,
) {
  final command = _ActivationCommand(source);
  try {
    return runZoned(action, zoneValues: {_activationCommandKey: command});
  } finally {
    command.active = false;
  }
}

class _ActivationCommand {
  _ActivationCommand(this.source);
  InteractionSource source;
  bool active = true;
}

/// Source for a legacy UI guard called without the initiating widget's context.
/// A command has its own async context; concurrent commands cannot overwrite it.
InteractionSource get currentStarBridgeActivationSource {
  final command = Zone.current[_activationCommandKey] as _ActivationCommand?;
  return command?.active == true ? command!.source : InteractionSource.pointer;
}

/// Initial reads mount outside the opening command's async zone. Inherit an
/// instantaneous dialog's keyboard origin until a real action supplies its
/// own source. Only wait decoration changes, never requests or persistence.
InteractionSource resolveStarBridgeInitialReadSource(
  BuildContext context,
  InteractionSource source,
) {
  if (source != InteractionSource.programmatic) return source;
  final command = Zone.current[_activationCommandKey] as _ActivationCommand?;
  if (command != null &&
      command.active &&
      command.source != InteractionSource.programmatic) {
    return command.source;
  }
  final route = ModalRoute.of(context);
  final opening = context
      .dependOnInheritedWidgetOfExactType<_StarBridgeInitialReadScope>();
  // A new typed route has its own opening fact. Never inherit an older
  // viewport across it; an in-route switch still overrides that route's fact.
  final knownRoute =
      route is StarBridgeInitialReadOrigin || route is SuiteDialogRoute;
  if (opening != null &&
      (!knownRoute || identical(opening.viewportRoute, route))) {
    return opening.source;
  }
  final element = context
      .getElementForInheritedWidgetOfExactType<StarBridgeActivationOrigin>();
  if (element?.widget case StarBridgeActivationOrigin origin) {
    if (origin.source.value == InteractionSource.keyboard &&
        (!knownRoute || identical(ModalRoute.of(element!), route))) {
      return InteractionSource.keyboard;
    }
  }
  if (route case StarBridgeInitialReadOrigin origin) {
    return origin.initialReadSource;
  }
  return route is SuiteDialogRoute && route.instant
      ? InteractionSource.keyboard
      : source;
}

/// A confirming action may become the final source of the pending command.
/// This closure can only update that command while it is still active.
ValueChanged<InteractionSource> captureStarBridgeActivationCompletion() {
  final command = Zone.current[_activationCommandKey] as _ActivationCommand?;
  return (source) {
    if (command?.active == true) command!.source = source;
  };
}

/// Read-only provenance of this awaited command, including a later confirming
/// action. Once it ends, the getter cannot label unrelated future work.
ValueGetter<InteractionSource> captureStarBridgeActivationSource() {
  final command = Zone.current[_activationCommandKey] as _ActivationCommand?;
  return () => command?.active == true
      ? command!.source
      : InteractionSource.programmatic;
}

/// Keeps source through an awaited UI command without changing business
/// callbacks. Work scheduled beyond its completion no longer inherits source.
Future<T> runStarBridgeActivation<T>(
  InteractionSource source,
  FutureOr<T> Function() action,
) async {
  final command = _ActivationCommand(source);
  try {
    return await runZoned(action, zoneValues: {_activationCommandKey: command});
  } finally {
    command.active = false;
  }
}
