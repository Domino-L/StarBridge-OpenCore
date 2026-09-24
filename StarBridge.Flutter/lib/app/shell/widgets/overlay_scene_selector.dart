import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/window/native_viewport_visibility.dart';

import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../chrome/shell_chrome_port.dart';
import '../chrome/shell_chrome_projection.dart';
import '../shell_layout_mode.dart';

class OverlaySceneSelector extends StatelessWidget {
  const OverlaySceneSelector({
    required this.projection,
    required this.port,
    required this.mode,
    super.key,
  });

  final OverlaySceneProjection projection;
  final ShellChromePort port;
  final ShellLayoutMode mode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final actual = projection.optionById(projection.actualSceneId);
    final preferred = projection.optionById(projection.preferredSceneId);
    final current = actual ?? preferred;
    final label = current == null
        ? strings.text('top.overlayScene')
        : current.label ?? strings.text(current.labelKey);
    final tooltip = projection.fallbackReasonKey == null
        ? '${strings.text('top.overlayScene')}：$label'
        : strings.text(projection.fallbackReasonKey!);

    final controlShape = RoundedRectangleBorder(
      borderRadius: tokens.shape.small,
    );
    return Tooltip(
      message: tooltip,
      child: NativeViewportMenu(
        builder: (onOpen, onClose) => MenuAnchor(
          onOpen: onOpen,
          onClose: onClose,
          menuChildren: projection.options
              .map(
                (option) => MenuItemButton(
                  onPressed: option.enabled && projection.canChange ? () =>
                      unawaited(port.selectOverlayScene(option.id)) : null,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: Text(option.label ?? strings.text(option.labelKey), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ),
              )
              .toList(),
          builder: (context, controller, _) => OutlinedButton(
            key: const Key('overlay-scene-selector'),
            onPressed: projection.canChange
                ? () =>
                      controller.isOpen ? controller.close() : controller.open()
                : null,
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(
                Size(
                  tokens.density.controlHeight,
                  tokens.density.controlHeight,
                ),
              ),
              maximumSize: WidgetStatePropertyAll(
                Size(
                  mode == ShellLayoutMode.wide
                      ? tokens.density.navigationCompact
                      : tokens.density.controlHeight,
                  tokens.density.controlHeight,
                ),
              ),
              padding: WidgetStatePropertyAll(
                mode == ShellLayoutMode.wide
                    ? EdgeInsetsDirectional.fromSTEB(
                        tokens.space.xs,
                        tokens.space.xxs,
                        tokens.space.sm,
                        tokens.space.xxs,
                      )
                    : EdgeInsets.zero,
              ),
              shape: WidgetStatePropertyAll(controlShape),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return tokens.surfaces.selected.fill;
                }
                return tokens.surfaces.chrome.fill;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.disabled)
                    ? tokens.colors.textDisabled
                    : tokens.colors.textPrimary;
              }),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return BorderSide(
                    color: tokens.colors.focusRing,
                    width: tokens.stroke.focusWidth,
                  );
                }
                return BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? tokens.surfaces.chrome.border
                      : tokens.surfaces.chrome.border,
                  width: tokens.stroke.regular,
                );
              }),
              overlayColor: WidgetStatePropertyAll(
                tokens.colors.accent.withValues(alpha: 0.10),
              ),
              elevation: const WidgetStatePropertyAll(0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SceneLens(enabled: projection.canChange),
                if (mode == ShellLayoutMode.wide) ...[
                  SizedBox(width: tokens.space.xs),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          strings.text('top.overlayScene'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(height: 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: tokens.space.xs),
                  StarBridgeIcon(
                    StarBridgeIconSemantic.menuDown,
                    size: tokens.icons.small,
                    color: projection.canChange
                        ? tokens.colors.textSecondary
                        : tokens.colors.textDisabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SceneLens extends StatelessWidget {
  const _SceneLens({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: tokens.icons.large,
      height: tokens.icons.large,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surfaces.raised.fill,
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: tokens.surfaces.raised.border,
          width: tokens.stroke.hairline,
        ),
      ),
      child: StarBridgeIcon(
        StarBridgeIconSemantic.scene,
        size: tokens.icons.small,
        color: enabled ? tokens.colors.accent : tokens.colors.textDisabled,
      ),
    );
  }
}
