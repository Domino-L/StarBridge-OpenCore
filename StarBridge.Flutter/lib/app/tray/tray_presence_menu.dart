import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_cascading_menu.dart';
import '../presence/manual_presence.dart';
import '../presence/manual_presence_menu.dart';
import '../presence/manual_presence_widgets.dart';

/// Presentation only. Selection keeps the popup open for the original
/// controller's pending/failure feedback, just like the native tray menu.
class TrayPresenceMenu extends StatelessWidget {
  const TrayPresenceMenu({required this.controller, super.key});
  final ManualPresenceController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => StarBridgeCascadingMenu(
      key: ValueKey((controller, controller.snapshot.scope)),
      label:
          '${manualPresenceText(context, 'presence.title')}\n'
          '${manualPresenceText(context, controller.selfKey)}',
      entries: manualPresenceEntries(context, controller),
      footer: manualPresenceMenuFeedback(context, controller),
      builder: (context, menu, focus, toggle) {
        final theme = Theme.of(context);
        final native = TextButton(
          onPressed: () {},
          child: const SizedBox.shrink(),
        );
        final style = (TextButtonTheme.of(context).style ?? const ButtonStyle())
            .merge(native.defaultStyleOf(context));
        final adjustment =
            (style.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
        final target =
            (style.tapTargetSize ?? theme.materialTapTargetSize) ==
                MaterialTapTargetSize.padded
            ? kMinInteractiveDimension
            : 0.0;
        return StarBridgeActionButton(
          controlKey: const Key('tray-presence-menu'),
          kind: StarBridgeActionKind.quiet,
          nativeStyle: style,
          minHeight: math.max(
            style.minimumSize!.resolve({})!.height + adjustment.dy,
            target + adjustment.dy,
          ),
          focusNode: focus,
          onActivate: toggle,
          child: Row(
            children: [
              Expanded(
                child: Text(manualPresenceText(context, 'presence.title')),
              ),
              ManualPresenceBadge(controller: controller),
              const SizedBox(width: 8),
              const StarBridgeIcon(StarBridgeIconSemantic.menuDown, size: 12),
            ],
          ),
        );
      },
    ),
  );
}
