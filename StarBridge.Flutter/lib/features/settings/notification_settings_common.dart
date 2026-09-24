import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final title = strings.text(titleKey);
    final description = strings.text(descriptionKey);
    return Semantics(
      container: true,
      enabled: enabled,
      toggled: value,
      label: title,
      hint: description,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          borderRadius: tokens.shape.small,
          child: Container(
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
                Switch(
                  key: settingKey,
                  value: value,
                  onChanged: enabled
                      ? (next) async {
                          await onChanged(next);
                        }
                      : null,
                ),
              ],
            ),
          ),
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
      child: Row(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.warning,
            size: tokens.icons.medium,
            color: tokens.colors.warning,
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(child: Text(strings.text(messageKey))),
          SizedBox(width: tokens.space.sm),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(strings.text('settings.notification.retry')),
          ),
        ],
      ),
    );
  }
}

class NotificationLoadingView extends StatelessWidget {
  const NotificationLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: tokens.space.md),
            Text(AppStrings.of(context).text('settings.notification.loading')),
          ],
        ),
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
                  OutlinedButton.icon(
                    onPressed: onAction,
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                    label: Text(strings.text(actionKey!)),
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
  const _InlineBadge({required this.label, this.color});

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
