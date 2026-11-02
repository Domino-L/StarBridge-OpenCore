import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import 'help_support_action.dart';

/// These native buttons are unmounted templates. Reuse the existing settings
/// adapter without replacing the original callbacks, guards or plain children.
class MaintenanceAction extends StatelessWidget {
  const MaintenanceAction(this.button, {super.key});
  final ButtonStyleButton button;

  @override
  Widget build(BuildContext context) {
    assert(
      button.key != null && button.style == null && button.onLongPress == null,
    );
    return HelpSupportAction(
      controlKey: button.key!,
      kind: switch (button) {
        FilledButton() => StarBridgeActionKind.primary,
        OutlinedButton() => StarBridgeActionKind.secondary,
        TextButton() => StarBridgeActionKind.quiet,
        _ => throw ArgumentError('Unsupported maintenance action'),
      },
      onActivate: button.onPressed == null ? null : (_) => button.onPressed!(),
      child: button.child!,
    );
  }
}
