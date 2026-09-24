import 'dart:async';

import 'package:flutter/material.dart';
import '../common/user_avatar_menu.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/scm_brand_mark.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/embedded_avatar.dart';
import 'account_models.dart';
import 'account_module.dart';
import 'account_view_components.dart';
import 'password_recovery_dialog.dart';
import 'legacy_password_login_dialog.dart';

enum AccountSignedOutReason {
  noSession,
  credentialTemporarilyUnavailable,
  reauthorizationRequired,
}

class AccountLoadingView extends StatelessWidget {
  const AccountLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Row(
        children: [
          SizedBox.square(
            dimension: tokens.icons.medium,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: tokens.space.md),
          Expanded(child: Text(strings.text('account.loading'))),
        ],
      ),
    );
  }
}

class AccountSignedOutView extends StatelessWidget {
  const AccountSignedOutView({
    required this.projection,
    required this.module,
    required this.reason,
    super.key,
  });

  final AccountProjection projection;
  final AccountModule module;
  final AccountSignedOutReason reason;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final signingIn = projection.operation == AccountOperation.signingIn;
    final cancelling = projection.operation == AccountOperation.cancellingLogin;
    final checkingConnection =
        projection.operation == AccountOperation.refreshing;
    final credentialUnavailable =
        reason == AccountSignedOutReason.credentialTemporarilyUnavailable;
    final reauthorization =
        reason == AccountSignedOutReason.reauthorizationRequired;
    final warning = reason != AccountSignedOutReason.noSession;
    final titleKey = switch (reason) {
      AccountSignedOutReason.noSession => 'account.signedOut.title',
      AccountSignedOutReason.credentialTemporarilyUnavailable =>
        'account.credentialUnavailable.title',
      AccountSignedOutReason.reauthorizationRequired =>
        'account.reauthorization.title',
    };
    final bodyKey = switch (reason) {
      AccountSignedOutReason.noSession => 'account.signedOut.body',
      AccountSignedOutReason.credentialTemporarilyUnavailable =>
        'account.credentialUnavailable.body',
      AccountSignedOutReason.reauthorizationRequired =>
        'account.reauthorization.body',
    };
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ScmBrandMark(key: Key('account-scm-brand-signed-out')),
                if (warning) ...[
                  SizedBox(width: tokens.space.md),
                  AccountSectionIcon(
                    semantic: StarBridgeIconSemantic.warning,
                    color: tokens.colors.warning,
                    background: tokens.colors.warningSoft,
                  ),
                ],
              ],
            ),
            SizedBox(height: tokens.space.lg),
            Text(
              strings.text(titleKey),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              strings.text(bodyKey),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
            SizedBox(height: tokens.space.lg),
            if (credentialUnavailable && checkingConnection) ...[
              LinearProgressIndicator(
                minHeight: tokens.stroke.strong,
                borderRadius: tokens.shape.small,
              ),
              SizedBox(height: tokens.space.sm),
              Text(
                strings.text('account.credentialUnavailable.checking'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (credentialUnavailable)
              FilledButton.icon(
                key: const Key('account-retry-session'),
                onPressed: projection.canRetrySessionRestore
                    ? () => unawaited(module.refresh())
                    : null,
                icon: StarBridgeIcon(StarBridgeIconSemantic.refresh),
                label: Text(
                  strings.text('account.credentialUnavailable.retry'),
                ),
              )
            else if (signingIn || cancelling) ...[
              LinearProgressIndicator(
                minHeight: tokens.stroke.strong,
                borderRadius: tokens.shape.small,
              ),
              SizedBox(height: tokens.space.sm),
              Text(
                strings.text(
                  cancelling
                      ? 'account.login.cancelling'
                      : 'account.login.waiting',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: tokens.space.md),
              OutlinedButton(
                key: const Key('account-cancel-login'),
                onPressed: cancelling
                    ? null
                    : () => unawaited(module.cancelLogin()),
                child: Text(strings.text('account.login.cancel')),
              ),
            ] else
              FilledButton.icon(
                key: Key(
                  reauthorization ? 'account-reauthorize' : 'account-login',
                ),
                onPressed: projection.canLogin
                    ? () => unawaited(module.beginLogin())
                    : null,
                icon: StarBridgeIcon(StarBridgeIconSemantic.login),
                label: Text(
                  strings.text(
                    reauthorization
                        ? 'account.reauthorization.action'
                        : 'account.login.action',
                  ),
                ),
              ),
            if (reason == AccountSignedOutReason.noSession &&
                module.legacyPasswordLogin != null) ...[
              SizedBox(height: tokens.space.sm),
              OutlinedButton(
                key: const Key('account-legacy-login'),
                onPressed: projection.isBusy
                    ? null
                    : () async {
                        await showLegacyPasswordLoginDialog(
                          context,
                          module.legacyPasswordLogin!,
                          recovery: module.passwordRecovery,
                        );
                        await module.refresh();
                      },
                child: Text(strings.text('account.legacyLogin.title')),
              ),
            ],
            if (module.passwordRecovery case final recovery?) ...[
              SizedBox(height: tokens.space.sm),
              TextButton(
                key: const Key('account-password-recovery'),
                onPressed: projection.isBusy
                    ? null
                    : () => unawaited(
                        showPasswordRecoveryDialog(context, recovery),
                      ),
                child: Text(strings.text('account.recovery.title')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AccountLegacySessionView extends StatelessWidget {
  const AccountLegacySessionView({
    required this.projection,
    required this.module,
    super.key,
  });
  final AccountProjection projection;
  final AccountModule module;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final unavailable =
        projection.sessionState == AccountSessionState.legacyUnavailable;
    final signingIn = projection.operation == AccountOperation.signingIn;
    final cancelling = projection.operation == AccountOperation.cancellingLogin;
    return StarBridgeSurface(
      key: const Key('account-legacy-session'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: tokens.shape.medium,
                child: SizedBox.square(
                  dimension: tokens.density.controlHeight * 1.35,
                  child: UserAvatarMenu(name: projection.profile?.displayName ?? '', isSelf: true, child: EmbeddedAvatar(
                    source: projection.profile?.avatarImageData,
                    fallback: StarBridgeIcon(StarBridgeIconSemantic.account),
                  )),
                ),
              ),
              SizedBox(width: tokens.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      projection.profile?.displayName ??
                          strings.text('account.legacySession.status'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (projection.profile?.maskedAccount case final label?)
                      SelectableText(label),
                    if (projection.identity.authoritativeHandle
                        case final handle?)
                      AccountLabelValue(
                        label: strings.text('account.identity.handle'),
                        value: handle,
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space.sm),
          Text(
            strings.text(
              unavailable
                  ? 'account.legacySession.unavailable'
                  : 'account.legacySession.status',
            ),
            style: TextStyle(
              color: unavailable
                  ? tokens.colors.warning
                  : tokens.colors.success,
            ),
          ),
          SizedBox(height: tokens.space.sm),
          Text(strings.text('account.legacySession.body')),
          SizedBox(height: tokens.space.md),
          if (signingIn || cancelling) ...[
            const LinearProgressIndicator(),
            SizedBox(height: tokens.space.sm),
            Text(
              strings.text(
                cancelling
                    ? 'account.login.cancelling'
                    : 'account.login.waiting',
              ),
            ),
            SizedBox(height: tokens.space.sm),
          ],
          Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.sm,
            children: [
              if (signingIn || cancelling)
                OutlinedButton(
                  key: const Key('account-cancel-login'),
                  onPressed: cancelling
                      ? null
                      : () => unawaited(module.cancelLogin()),
                  child: Text(strings.text('account.login.cancel')),
                )
              else
                OutlinedButton(
                  key: const Key('account-login'),
                  onPressed: projection.canLogin
                      ? () => unawaited(module.beginLogin())
                      : null,
                  child: Text(strings.text('account.login.action')),
                ),
              OutlinedButton(
                key: const Key('account-legacy-refresh'),
                onPressed: projection.isBusy
                    ? null
                    : () => unawaited(module.refresh()),
                child: Text(strings.text('account.legacySession.refresh')),
              ),
              TextButton(
                key: const Key('account-legacy-logout'),
                onPressed: projection.canLogout
                    ? () => unawaited(module.logout())
                    : null,
                child: Text(strings.text('account.logout.action')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
