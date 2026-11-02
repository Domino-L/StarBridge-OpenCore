import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';

/// Non-interactive text hint only. Rich/actionable popovers keep their own
/// focus and dismissal contract; this does not replace those controls.
class StarBridgeTooltip extends StatelessWidget {
  const StarBridgeTooltip({
    required this.message,
    required this.child,
    this.excludeFromSemantics = false,
    this.waitDuration = const Duration(milliseconds: 450),
    this.onVisibilityChanged,
    this.consumeEscape = true,
    super.key,
  });

  final String message;
  final Widget child;
  final bool excludeFromSemantics;
  final Duration waitDuration;
  final ValueChanged<bool>? onVisibilityChanged;
  final bool consumeEscape;

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: SuiteTooltip(
      message: message,
      excludeFromSemantics: excludeFromSemantics,
      waitDuration: waitDuration,
      onVisibilityChanged: onVisibilityChanged,
      consumeEscape: consumeEscape,
      showDuration:
          TooltipTheme.of(context).showDuration ??
          const Duration(milliseconds: 1500),
      child: child,
    ),
  );
}
