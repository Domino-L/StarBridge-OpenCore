import 'package:flutter/material.dart';

import 'overlay_source_menu.dart';
import '../../../design_system/interaction/starbridge_action_button.dart';
import '../../../design_system/interaction/starbridge_tooltip.dart';

import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../chrome/shell_chrome_port.dart';
import '../chrome/shell_chrome_projection.dart';
import '../chrome/overlay_source_labels.dart';
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
    final label = overlaySourceLabel(projection, strings);
    final tooltip = projection.fallbackReasonKey == null
        ? '$label\n${strings.text(overlaySourceHint(projection))}'
        : strings.text(projection.fallbackReasonKey!);
    final primaryStyle = Theme.of(context).textTheme.labelLarge;
    final secondaryStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(height: 1);
    final subtitle = strings.text('top.overlayScene');
    double lineHeight(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      try {
        return painter.height;
      } finally {
        painter.dispose();
      }
    }

    // The chrome owns a fixed-height slot. Keep the selected source at the
    // user's font size; only omit the constant subtitle when both lines do not
    // fit. Do not scale text down or enlarge/reflow the whole title bar.
    final showSubtitle =
        lineHeight(label, primaryStyle) +
            lineHeight(subtitle, secondaryStyle) <=
        tokens.density.controlHeight - 2 * tokens.space.xxs;
    final primaryLabel = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: primaryStyle,
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: tokens.shape.small,
    );
    return StarBridgeTooltip(
      message: tooltip,
      consumeEscape: false,
      child: OverlaySourceMenu(
        projection: projection,
        onSelected: port.selectOverlayScene,
        triggerBuilder: (context, controller, focus, toggle) =>
            StarBridgeActionButton(
              controlKey: const Key('overlay-scene-selector'),
              focusNode: focus,
              onActivate: projection.canChange ? toggle : null,
              minHeight: tokens.density.controlHeight,
              nativeStyle: ButtonStyle(
                minimumSize: WidgetStatePropertyAll(
                  Size(
                    tokens.density.controlHeight,
                    tokens.density.controlHeight,
                  ),
                ),
                maximumSize: WidgetStatePropertyAll(
                  Size(
                    mode == ShellLayoutMode.wide
                        ? double.infinity
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
                  return Colors.transparent;
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
                  return BorderSide.none;
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
                      child: showSubtitle
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                primaryLabel,
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: secondaryStyle,
                                ),
                              ],
                            )
                          : primaryLabel,
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
      child: StarBridgeIcon(
        StarBridgeIconSemantic.scene,
        size: tokens.icons.small,
        color: enabled ? tokens.colors.accent : tokens.colors.textDisabled,
      ),
    );
  }
}
