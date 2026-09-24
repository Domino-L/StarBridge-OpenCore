import 'package:flutter/material.dart';

import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../../runtime/example_scene_control.dart';
import '../shell_layout_mode.dart';

class ExampleSceneButton extends StatelessWidget {
  const ExampleSceneButton({
    required this.control,
    required this.mode,
    super.key,
  });

  final ExampleSceneControl control;
  final ShellLayoutMode mode;

  @override
  Widget build(BuildContext context) {
    if (!control.visible || control.onToggle == null) {
      return const SizedBox.shrink();
    }
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final tooltip = strings.text(
      control.active ? 'exampleScene.exit' : 'exampleScene.open',
    );
    final foreground = control.active
        ? tokens.colors.warning
        : tokens.colors.textSecondary;
    final background = control.active
        ? tokens.colors.warningSoft
        : tokens.surfaces.status.fill;
    final side = BorderSide(
      color: control.active
          ? tokens.colors.warning
          : tokens.surfaces.status.border,
      width: tokens.stroke.regular,
    );
    final icon = StarBridgeIcon(
      StarBridgeIconSemantic.scene,
      size: tokens.icons.small,
      color: foreground,
    );

    if (mode == ShellLayoutMode.iconOnly) {
      return Tooltip(
        message: tooltip,
        child: IconButton.outlined(
          key: Key(
            control.active ? 'example-scene-exit' : 'example-scene-open',
          ),
          onPressed: control.onToggle,
          style: IconButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: background,
            side: side,
          ),
          icon: icon,
        ),
      );
    }

    final label = strings.text(
      control.active
          ? 'exampleScene.exit'
          : mode == ShellLayoutMode.compact
          ? 'exampleScene.compact'
          : 'exampleScene.open',
    );
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        key: Key(control.active ? 'example-scene-exit' : 'example-scene-open'),
        onPressed: control.onToggle,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          side: side,
          minimumSize: Size(0, tokens.density.controlHeight),
          padding: EdgeInsets.symmetric(horizontal: tokens.space.md),
        ),
        icon: icon,
        label: Text(label),
      ),
    );
  }
}
