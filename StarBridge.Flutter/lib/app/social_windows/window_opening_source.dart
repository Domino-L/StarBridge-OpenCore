import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../platform/window/menu_read_feedback.dart';

/// Display provenance only; not a scope, credential, permission or request id.
InteractionSource captureWindowOpeningSource() {
  final source = captureStarBridgeActivationSource()();
  if (source != InteractionSource.programmatic) return source;
  return switch (currentMenuReadOrigin) {
    MenuReadOrigin.pointer => InteractionSource.pointer,
    MenuReadOrigin.keyboard => InteractionSource.keyboard,
    _ => InteractionSource.programmatic,
  };
}

InteractionSource decodeWindowOpeningSource(Object? value) => switch (value) {
  'pointer' => InteractionSource.pointer,
  'keyboard' => InteractionSource.keyboard,
  _ => InteractionSource.programmatic,
};
