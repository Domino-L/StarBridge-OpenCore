import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_models.dart';

class AccountMessagePanel extends StatelessWidget {
  const AccountMessagePanel({
    required this.kind,
    required this.messageKey,
    this.actionKey,
    this.onAction,
    super.key,
  });

  final AccountNoticeKind kind;
  final String messageKey;
  final String? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final (color, background, icon) = switch (kind) {
      AccountNoticeKind.success => (
        tokens.colors.success,
        tokens.colors.successSoft,
        StarBridgeIconSemantic.connected,
      ),
      AccountNoticeKind.warning => (
        tokens.colors.warning,
        tokens.colors.warningSoft,
        StarBridgeIconSemantic.warning,
      ),
      AccountNoticeKind.failure => (
        tokens.colors.danger,
        tokens.colors.dangerSoft,
        StarBridgeIconSemantic.disconnected,
      ),
      AccountNoticeKind.information => (
        tokens.colors.info,
        tokens.colors.infoSoft,
        StarBridgeIconSemantic.statusIdentity,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: tokens.shape.small,
        border: Border.all(color: color, width: tokens.stroke.regular),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.space.md),
        child: Row(
          children: [
            StarBridgeIcon(icon, color: color),
            SizedBox(width: tokens.space.sm),
            Expanded(child: Text(strings.text(messageKey))),
            if (actionKey case final key?)
              TextButton(onPressed: onAction, child: Text(strings.text(key))),
          ],
        ),
      ),
    );
  }
}

class AccountCardHeading extends StatelessWidget {
  const AccountCardHeading({
    required this.semantic,
    required this.titleKey,
    required this.bodyKey,
    this.color,
    super.key,
  });

  final StarBridgeIconSemantic semantic;
  final String titleKey;
  final String bodyKey;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StarBridgeIcon(
          semantic,
          color: color ?? tokens.colors.accent,
          size: tokens.icons.medium,
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
                strings.text(bodyKey),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AccountInlineNotice extends StatelessWidget {
  const AccountInlineNotice({
    required this.icon,
    required this.textKey,
    required this.color,
    required this.background,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String textKey;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: tokens.shape.small,
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarBridgeIcon(icon, size: tokens.icons.small, color: color),
            SizedBox(width: tokens.space.xs),
            Expanded(
              child: Text(
                AppStrings.of(context).text(textKey),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountFreshnessBadge extends StatelessWidget {
  const AccountFreshnessBadge({required this.freshness, super.key});

  final AccountProfileFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final (labelKey, color, background) = switch (freshness) {
      AccountProfileFreshness.live => (
        'account.source.live',
        tokens.colors.success,
        tokens.colors.successSoft,
      ),
      AccountProfileFreshness.cached => (
        'account.source.cached',
        tokens.colors.warning,
        tokens.colors.warningSoft,
      ),
      AccountProfileFreshness.unavailable => (
        'account.source.unavailable',
        tokens.colors.offline,
        tokens.surfaces.status.fill,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: tokens.shape.pill,
        border: Border.all(color: color, width: tokens.stroke.hairline),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          tokens.space.sm,
          tokens.space.xxs,
          tokens.space.sm,
          tokens.space.xxs,
        ),
        child: Text(
          strings.text(labelKey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: color),
        ),
      ),
    );
  }
}

class AccountLabelValue extends StatelessWidget {
  const AccountLabelValue({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.xxs),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class AccountSectionIcon extends StatelessWidget {
  const AccountSectionIcon({
    required this.semantic,
    required this.color,
    required this.background,
    super.key,
  });

  final StarBridgeIconSemantic semantic;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: tokens.density.controlHeight,
      height: tokens.density.controlHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: tokens.shape.medium,
      ),
      child: StarBridgeIcon(semantic, color: color, size: tokens.icons.medium),
    );
  }
}

({StarBridgeIconSemantic icon, String bodyKey, Color color, Color background})
accountIdentityPresentation(
  AccountIdentityState state,
  StarBridgeTokens tokens,
) {
  return switch (state) {
    AccountIdentityState.match => (
      icon: StarBridgeIconSemantic.connected,
      bodyKey: 'account.identity.match',
      color: tokens.colors.success,
      background: tokens.colors.successSoft,
    ),
    AccountIdentityState.mismatch => (
      icon: StarBridgeIconSemantic.warning,
      bodyKey: 'account.identity.mismatch',
      color: tokens.colors.warning,
      background: tokens.colors.warningSoft,
    ),
    AccountIdentityState.awaitingGameIdentity => (
      icon: StarBridgeIconSemantic.pending,
      bodyKey: 'account.identity.awaiting',
      color: tokens.colors.info,
      background: tokens.colors.infoSoft,
    ),
    AccountIdentityState.reverifyRequired => (
      icon: StarBridgeIconSemantic.warning,
      bodyKey: 'account.identity.reverify',
      color: tokens.colors.warning,
      background: tokens.colors.warningSoft,
    ),
    AccountIdentityState.revoked => (
      icon: StarBridgeIconSemantic.disconnected,
      bodyKey: 'account.identity.revoked',
      color: tokens.colors.danger,
      background: tokens.colors.dangerSoft,
    ),
    AccountIdentityState.unknown || AccountIdentityState.unavailable => (
      icon: StarBridgeIconSemantic.statusIdentity,
      bodyKey: 'account.identity.unknown',
      color: tokens.colors.offline,
      background: tokens.surfaces.status.fill,
    ),
  };
}
