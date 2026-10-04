import 'dart:async';

import 'package:flutter/material.dart';

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
  final Widget Function(BuildContext, MenuController)? triggerBuilder;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return NativeViewportMenu(
      builder: (onOpen, onClose) => MenuAnchor(
        onOpen: onOpen,
        onClose: onClose,
        menuChildren: [
          for (final option in projection.options)
            MenuItemButton(
              onPressed: option.enabled && projection.canChange
                  ? () => unawaited(onSelected(option.id))
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  overlaySourceOptionLabel(projection, option, strings),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        builder: (context, controller, _) =>
            triggerBuilder?.call(context, controller) ??
            OutlinedButton(
              key: triggerKey,
              onPressed: projection.canChange
                  ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      overlaySourceLabel(projection, strings),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
