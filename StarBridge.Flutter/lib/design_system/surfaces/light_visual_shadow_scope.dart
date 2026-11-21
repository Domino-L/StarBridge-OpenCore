import 'package:flutter/material.dart';

import '../../app/runtime/frame_governor.dart';
import 'light_visual_text.dart';

/// Tooltip overlays inherit this decoration from the fleet and trading hall.
/// Token values stay unchanged, including the full-quality shadow definitions.
class LightVisualShadowScope extends StatelessWidget {
  const LightVisualShadowScope({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: lightVisuals(),
    child: child,
    builder: (context, lightOnly, child) {
      final data = TooltipTheme.of(context);
      final decoration = data.decoration;
      final resolved = lightOnly && decoration is BoxDecoration
          ? data.copyWith(decoration: decoration.copyWith(boxShadow: const []))
          : data;
      final theme = Theme.of(context);
      return Theme(
        // Filter dialogs explicitly capture ThemeData, while other overlays
        // capture TooltipTheme. Both see the same scoped decoration.
        data: lightOnly ? theme.copyWith(tooltipTheme: resolved) : theme,
        child: TooltipTheme(
          data: resolved,
          child: LightVisualsFlag(light: lightOnly, child: child!),
        ),
      );
    },
  );
}
