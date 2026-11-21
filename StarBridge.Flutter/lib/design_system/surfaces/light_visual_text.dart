import 'package:flutter/widgets.dart';

/// Whether the fleet or trading hall page above is drawing light visuals.
/// Provided by LightVisualShadowScope; absent elsewhere (for example in
/// overlays above the page), where text keeps its full look.
class LightVisualsFlag extends InheritedWidget {
  const LightVisualsFlag({
    required this.light,
    required super.child,
    super.key,
  });

  final bool light;

  @override
  bool updateShouldNotify(LightVisualsFlag oldWidget) =>
      oldWidget.light != light;
}

/// A fading overflow draws through an offscreen layer whenever the text really
/// overflows; with many cards on screen that is one pass per card while a game
/// runs. Light visuals cut such text with an ellipsis instead
/// (review CX-C-FULL-073-REVIEW).
TextOverflow fadeOverflow(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<LightVisualsFlag>()?.light ==
        true
    ? TextOverflow.ellipsis
    : TextOverflow.fade;
