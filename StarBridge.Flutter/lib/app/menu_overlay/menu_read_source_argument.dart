import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../platform/window/menu_read_feedback.dart';

/// Optional display-only annotation, before the original transport handoff.
/// No active activation lease means programmatic, never the UI's pointer default.
Object? menuReadSourceArgument(String method, Object? argument) {
  final source = captureStarBridgeActivationSource()();
  if (source.name == 'programmatic' || !isMenuReadIntent(method, argument)) {
    return argument;
  }
  return {...argument as Map, 'motionSource': source.name};
}
