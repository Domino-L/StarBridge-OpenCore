import 'package:flutter/material.dart';

import 'dart:async';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class NotificationSettingsPanel extends StatelessWidget {
  const NotificationSettingsPanel({
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
    required this.child,
    this.accentColor,
    this.trailing,
    this.role = SurfaceRole.panel,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String descriptionKey;
  final Widget child;
  final Color? accentColor;
  final Widget? trailing;
  final SurfaceRole role;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: role,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (accentColor ?? tokens.colors.textSecondary)
                      .withValues(alpha: 0.12),
                  borderRadius: tokens.shape.small,
                ),
                child: StarBridgeIcon(
                  icon,
                  size: tokens.icons.medium,
                  color: accentColor ?? tokens.colors.textSecondary,
                ),
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text(titleKey),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      strings.text(descriptionKey),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: tokens.space.sm),
                trailing!,
              ],
            ],
          ),
          SizedBox(height: tokens.space.md),
          child,
        ],
      ),
    );
  }
}

class NotificationToggleRow extends StatelessWidget {
  const NotificationToggleRow({
    required this.settingKey,
    required this.titleKey,
    required this.descriptionKey,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.leading,
    this.showDivider = true,
    this.badgeKey,
    this.recommendKey,
    super.key,
  });

  final Key settingKey;
  final String titleKey;
  final String descriptionKey;
  final bool value;
  final bool enabled;
  final Future<bool> Function(bool value) onChanged;
  final Widget? leading;
  final bool showDivider;
  final String? badgeKey;

  /// Accent badge for a recommended choice the user has not made yet.
  final String? recommendKey;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final title = strings.text(titleKey);
    final description = strings.text(descriptionKey);
    return StarBridgeSwitch.tile(
      value: value,
      label: title,
      subtitle: description,
      controlKey: settingKey,
      onChanged: enabled
          ? (next) {
              onChanged(next);
            }
          : null,
      rowBuilder: (control) => Container(
        padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: tokens.surfaces.panel.border,
                    width: tokens.stroke.hairline,
                  ),
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              Padding(
                padding: EdgeInsets.only(top: tokens.space.xxs),
                child: leading,
              ),
              SizedBox(width: tokens.space.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (badgeKey != null) ...[
                        SizedBox(width: tokens.space.xs),
                        _InlineBadge(label: strings.text(badgeKey!)),
                      ],
                      if (recommendKey != null) ...[
                        SizedBox(width: tokens.space.xs),
                        _InlineBadge(
                          key: const Key('notification-recommended'),
                          label: strings.text(recommendKey!),
                          color: tokens.colors.accent,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: tokens.space.xxs),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? tokens.colors.textSecondary
                          : tokens.colors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: tokens.space.md),
            control,
          ],
        ),
      ),
    );
  }
}

class NotificationReadOnlyRow extends StatelessWidget {
  const NotificationReadOnlyRow({
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
    required this.statusKey,
    required this.color,
    this.showDivider = true,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String descriptionKey;
  final String statusKey;
  final Color color;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: tokens.surfaces.panel.border,
                  width: tokens.stroke.hairline,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(icon, size: tokens.icons.medium, color: color),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(height: tokens.space.xxs),
                Text(
                  strings.text(descriptionKey),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.space.md),
          _InlineBadge(label: strings.text(statusKey), color: color),
        ],
      ),
    );
  }
}

class NotificationFailureBanner extends StatelessWidget {
  const NotificationFailureBanner({
    required this.messageKey,
    required this.onRetry,
    super.key,
  });

  final String messageKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: tokens.colors.warningSoft,
        border: Border.all(
          color: tokens.colors.warning,
          width: tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final message = Row(
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.warning,
                size: tokens.icons.medium,
                color: tokens.colors.warning,
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(child: Text(strings.text(messageKey))),
            ],
          );
          final retry = StarBridgeActionButton(
            controlKey: const Key('notification-failure-retry'),
            tone: ActionTone.warning,
            semanticLabel: strings.text('settings.notification.retry'),
            onActivate: (source) =>
                unawaited(runStarBridgeActivation<void>(source, onRetry)),
            child: Text(strings.text('settings.notification.retry')),
          );
          // Give long copy its own row rather than shrinking the configured
          // text scale. Keep the element path stable across the breakpoint so
          // resizing does not retire the focused retry action.
          final stacked =
              constraints.maxWidth <
              440 * (MediaQuery.textScalerOf(context).scale(14) / 14);
          return Flex(
            direction: stacked ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              Flexible(fit: FlexFit.loose, child: message),
              SizedBox(
                width: stacked ? 0 : tokens.space.sm,
                height: stacked ? tokens.space.sm : 0,
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                widthFactor: stacked ? null : 1,
                child: retry,
              ),
            ],
          );
        },
      ),
    );
  }
}

class NotificationLoadingView extends StatefulWidget {
  const NotificationLoadingView({
    this.source = InteractionSource.programmatic,
    super.key,
  });

  final InteractionSource source;

  @override
  State<NotificationLoadingView> createState() =>
      _NotificationLoadingViewState();
}

class _NotificationLoadingViewState extends State<NotificationLoadingView> {
  InteractionSource? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Freeze this phase's opening fact; a later viewport action cannot relabel it.
    _source ??= resolveStarBridgeInitialReadSource(context, widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeInteractionRegion(
      child: Builder(
        builder: (context) {
          final data = InteractionScope.of(context);
          return InteractionScope(
            data: data.copyWith(
              reduceMotion:
                  data.reduceMotion || _source == InteractionSource.keyboard,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(tokens.space.xl),
                child: SuiteBusyFrame(
                  busy: true,
                  child: Padding(
                    padding: EdgeInsets.all(tokens.space.md),
                    child: SuiteBusyLabel(
                      AppStrings.of(context)
                          .text('settings.notification.loading'),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class NotificationStateView extends StatelessWidget {
  const NotificationStateView({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    this.actionKey,
    this.onAction,
    this.warning = false,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String bodyKey;
  final String? actionKey;
  final Future<void> Function()? onAction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.space.xl),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: StarBridgeSurface(
            role: SurfaceRole.raised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarBridgeIcon(
                  icon,
                  size: tokens.icons.large,
                  color: warning ? tokens.colors.warning : tokens.colors.accent,
                ),
                SizedBox(height: tokens.space.md),
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: tokens.space.xs),
                Text(
                  strings.text(bodyKey),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                if (actionKey != null && onAction != null) ...[
                  SizedBox(height: tokens.space.lg),
                  StarBridgeActionButton(
                    controlKey: const Key('notification-state-action'),
                    semanticLabel: strings.text(actionKey!),
                    onActivate: (source) => unawaited(
                      runStarBridgeActivation<void>(source, onAction!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                        const SizedBox(width: 8),
                        Text(strings.text(actionKey!)),
                      ],
                    ),
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

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({required this.label, this.color, super.key});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final resolved = color ?? tokens.colors.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.xs,
        vertical: tokens.space.xxs,
      ),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.11),
        border: Border.all(
          color: resolved.withValues(alpha: 0.36),
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: resolved),
      ),
    );
  }
}
