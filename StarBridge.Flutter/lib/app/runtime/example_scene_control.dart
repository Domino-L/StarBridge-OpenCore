import 'package:flutter/foundation.dart';

@immutable
final class ExampleSceneControl {
  const ExampleSceneControl.hidden()
    : visible = false,
      active = false,
      onToggle = null;

  const ExampleSceneControl.available({
    required this.active,
    required this.onToggle,
  }) : visible = true;

  final bool visible;
  final bool active;
  final VoidCallback? onToggle;
}
