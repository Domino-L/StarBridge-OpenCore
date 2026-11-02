import 'package:flutter/widgets.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_activation_origin.dart';

/// An explicit exit still passes through the runtime's close/unsaved guards.
class ExitApplicationIntent extends Intent {
  const ExitApplicationIntent({this.beforeExit, this.source});

  /// Transient UI origin for leave-guard presentation, never exit authorization.
  final InteractionSource? source;

  /// Prepare a confirmed update only after all unsaved/leave guards pass.
  /// A failed helper handoff must keep the current client running.
  final Future<bool> Function()? beforeExit;

  /// Keep the UI origin alive through async guards; the callback still owns
  /// every close/leave/installation decision and its original ordering.
  Future<void> runWithSource(Future<void> Function() action) =>
      runStarBridgeActivation<void>(
        source ?? currentStarBridgeActivationSource,
        action,
      );
}
