import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../../design_system/interaction/starbridge_action_button.dart';
import '../../../design_system/interaction/starbridge_activation_origin.dart';
import '../../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../../platform/window/native_viewport_visibility.dart';
import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../localization/app_strings.dart';
import '../chrome/overlay_source_labels.dart';
import '../chrome/shell_chrome_projection.dart';

/// One menu for shell and settings. Callers may size its trigger to the available
/// chrome, but options, disabled choices, labels and native viewport handling
/// cannot drift into separate implementations.
class OverlaySourceMenu extends StatelessWidget {
  const OverlaySourceMenu({
    required this.projection,
    required this.onSelected,
    this.triggerKey,
    this.triggerBuilder,
    super.key,
  });
  final OverlaySceneProjection projection;
  final Future<Object?> Function(String id) onSelected;
  final Key? triggerKey;
  final Widget Function(
    BuildContext,
    MenuController,
    FocusNode,
    ValueChanged<InteractionSource>,
  )?
  triggerBuilder;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return NativeViewportMenu(
      builder: (onOpen, onClose) => StarBridgeMenuAnchor(
        enabled: projection.canChange,
        retainExitContent:
            projection.canChange ||
            projection.fallbackReasonKey == 'overlay.source.saving',
        semanticLabel: overlaySourceLabel(projection, strings),
        onOpen: onOpen,
        onClose: onClose,
        entries: [
          for (final option in projection.options)
            StarBridgeMenuEntry(
              id: 'overlay-source-${option.id}',
              label: overlaySourceOptionLabel(projection, option, strings),
              onActivate: option.enabled && projection.canChange
                  ? (source) => unawaited(
                      runStarBridgeActivation<Object?>(
                        source,
                        () => onSelected(option.id),
                      ),
                    )
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  overlaySourceOptionLabel(projection, option, strings),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ),
        ],
        builder: (context, controller, focus, toggle) =>
            triggerBuilder?.call(context, controller, focus, toggle) ??
            StarBridgeActionButton(
              controlKey: triggerKey,
              focusNode: focus,
              onActivate: projection.canChange ? toggle : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      overlaySourceLabel(projection, strings),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const StarBridgeIcon(
                    StarBridgeIconSemantic.menuDown,
                    size: 18,
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
