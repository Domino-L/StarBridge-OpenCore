import 'package:flutter/material.dart';

import 'dart:async';

import '../../presence/account_presence_scope.dart';
import '../../presence/manual_presence_widgets.dart';
import '../../presence/manual_presence.dart';
import 'account_identity_button.dart';

import '../../../shared/embedded_avatar.dart';

import '../../../platform/window/native_viewport_visibility.dart';

import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../feature_registry.dart';
import '../../localization/app_strings.dart';
import '../chrome/shell_chrome_projection.dart';
import '../chrome/presence_color.dart';
import '../chrome/presence_label.dart';

class AccountMenu extends StatelessWidget {
  const AccountMenu({
    required this.destinations,
    required this.projection,
    required this.expanded,
    required this.onSelect,
    required this.onLogin,
    required this.onLogout,
    required this.onIssueAction,
    this.manualPresence,
    this.accountHandle,
    super.key,
  });

  final List<FeatureDescriptor> destinations;
  final ShellChromeProjection projection;
  final bool expanded;
  final ValueChanged<FeatureDescriptor> onSelect;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final VoidCallback onIssueAction;
  final ManualPresenceController? manualPresence;
  final String? accountHandle;

  @override
  Widget build(BuildContext context) {
    final scope = AccountPresenceScope.maybeOf(context);
    final manual = manualPresence ?? scope?.connection?.source.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([?manual, ?scope?.account]),
      builder: (context, _) => _buildMenu(context, scope),
    );
  }

  Widget _buildMenu(BuildContext context, AccountPresenceScope? scope) {
    final manual = manualPresence ?? scope?.connection?.source.controller;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: NativeViewportMenu(
        builder: (onOpen, onClose) => MenuAnchor(
          onOpen: () {
            onOpen();
            unawaited(scope?.connection?.refresh());
          },
          onClose: onClose,
          crossAxisUnconstrained: false,
          alignmentOffset: Offset(0, tokens.space.xs),
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(
              tokens.surfaces.floating.fill,
            ),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            side: WidgetStatePropertyAll(
              BorderSide(
                color: tokens.surfaces.floating.border,
                width: tokens.stroke.regular,
              ),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: tokens.shape.medium),
            ),
            padding: WidgetStatePropertyAll(EdgeInsets.all(tokens.space.xs)),
            maximumSize: const WidgetStatePropertyAll(Size(340, 520)),
          ),
          menuChildren: [
            _AccountMenuHeader(projection: projection),
            if (manual != null && projection.accountSignedIn)
              MenuAnchor(
                style: MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    tokens.surfaces.floating.fill,
                  ),
                  surfaceTintColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: tokens.surfaces.floating.border),
                  ),
                ),
                menuChildren: [ManualPresenceChoices(controller: manual)],
                builder: (context, controller, _) => MenuItemButton(
                  key: const Key('account-presence-menu'),
                  closeOnActivate: false,
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  trailingIcon: const StarBridgeIcon(
                    StarBridgeIconSemantic.forward,
                    size: 12,
                  ),
                  child: ManualPresenceBadge(controller: manual),
                ),
              ),
            if (projection.accountIssue case final issue?)
              MenuItemButton(
                key: const Key('account-issue-action'),
                onPressed: projection.accountBusy ? null : onIssueAction,
                leadingIcon: StarBridgeIcon(
                  issue.domain == ConnectionStatusDomain.identity
                      ? StarBridgeIconSemantic.login
                      : StarBridgeIconSemantic.refresh,
                  size: tokens.icons.medium,
                  color: _accountIssueTone(tokens, issue).foreground,
                ),
                child: Text(
                  strings.text(
                    issue.domain == ConnectionStatusDomain.identity
                        ? 'account.reauthorization.action'
                        : 'account.action.retry',
                  ),
                  style: TextStyle(
                    color: _accountIssueTone(tokens, issue).foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Divider(height: tokens.space.md),
            for (final descriptor in destinations)
              MenuItemButton(
                key: Key('account-menu-${descriptor.id}'),
                onPressed: () => onSelect(descriptor),
                leadingIcon: StarBridgeIcon(
                  descriptor.icon,
                  size: tokens.icons.medium,
                ),
                trailingIcon: StarBridgeIcon(
                  StarBridgeIconSemantic.forward,
                  size: tokens.icons.small,
                ),
                child: Text(
                  strings.text(descriptor.labelKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (projection.accountIssue == null || projection.accountSignedIn)
              Divider(height: tokens.space.md),
            if (projection.accountIssue == null || projection.accountSignedIn)
              MenuItemButton(
                key: Key(
                  projection.accountSignedIn
                      ? 'account-menu-logout'
                      : 'account-menu-login',
                ),
                onPressed: projection.accountBusy
                    ? null
                    : projection.accountSignedIn
                    ? onLogout
                    : onLogin,
                leadingIcon: StarBridgeIcon(
                  projection.accountSignedIn
                      ? StarBridgeIconSemantic.logout
                      : StarBridgeIconSemantic.login,
                  size: tokens.icons.medium,
                  color: projection.accountSignedIn
                      ? tokens.colors.danger
                      : null,
                ),
                child: Text(
                  strings.text(
                    projection.accountSignedIn
                        ? 'account.logout.action'
                        : 'account.login.menu',
                  ),
                  style: projection.accountSignedIn
                      ? TextStyle(color: tokens.colors.danger)
                      : null,
                ),
              ),
          ],
          builder: (context, controller, child) =>
              manual != null && projection.accountSignedIn
              ? AccountIdentityButton(
                  avatar: _AccountAvatar(
                    imageData: projection.accountAvatarImageData,
                    label: _accountDisplayLabel(strings, projection),
                    signedIn: projection.accountSignedIn,
                    loading: _accountIdentityIsLoading(projection),
                    presenceColor: presenceColor(
                      tokens.colors,
                      manual.snapshot.selfKey,
                    ),
                    issueColor: projection.accountIssue == null
                        ? null
                        : _accountIssueTone(
                            tokens,
                            projection.accountIssue!,
                          ).foreground,
                  ),
                  name: _accountDisplayLabel(strings, projection),
                  gameId:
                      accountHandle ??
                      scope?.account.value.identity.authoritativeHandle,
                  issueLabel: projection.accountIssue == null
                      ? null
                      : strings.text(projection.accountIssue!.titleKey),
                  compact: !expanded,
                  menuOpen: controller.isOpen,
                  presence: manual,
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                )
              : _AccountButton(
                  projection: projection,
                  expanded: expanded,
                  menuOpen: controller.isOpen,
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
        ),
      ),
    );
  }
}

class _AccountMenuHeader extends StatelessWidget {
  const _AccountMenuHeader({required this.projection});

  final ShellChromeProjection projection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final issue = projection.accountIssue;
    final issueTone = issue == null ? null : _accountIssueTone(tokens, issue);
    final accountLabel = _accountDisplayLabel(strings, projection);
    final accountLoading = _accountIdentityIsLoading(projection);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 276),
      child: Padding(
        padding: EdgeInsets.all(tokens.space.sm),
        child: Row(
          children: [
            _AccountAvatar(
              imageData: projection.accountAvatarImageData,
              label: accountLabel,
              signedIn: projection.accountSignedIn,
              loading: accountLoading,
              presenceColor: presenceColor(
                tokens.colors,
                projection.displayPresenceKey,
              ),
              issueColor: issueTone?.foreground,
            ),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accountLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SizedBox(height: tokens.space.xxs),
                  Text(
                    issue == null
                        ? '${strings.text(projection.presenceKey)} · '
                              '${strings.text(projection.syncKey)}'
                        : strings.text(issue.titleKey),
                    key: const Key('account-app-presence'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          issueTone?.foreground ??
                          presenceColor(tokens.colors, projection.presenceKey),
                      fontWeight: issue == null ? null : FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: tokens.space.xxs),
                  Text(
                    gamePresenceLabel(strings, projection),
                    key: const Key('account-game-presence'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: presenceColor(
                        tokens.colors,
                        projection.gamePresenceKey,
                      ),
                    ),
                  ),
                  if (issue != null) ...[
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      strings.text(issue.detailKey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.projection,
    required this.expanded,
    required this.menuOpen,
    required this.onPressed,
  });

  final ShellChromeProjection projection;
  final bool expanded;
  final bool menuOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final accountLabel = _accountDisplayLabel(strings, projection);
    final accountLoading = _accountIdentityIsLoading(projection);
    final issue = projection.accountIssue;
    final issueTone = issue == null ? null : _accountIssueTone(tokens, issue);
    final issueTitle = issue == null ? null : strings.text(issue.titleKey);
    final issueDetail = issue == null ? null : strings.text(issue.detailKey);
    final tooltip = issue == null
        ? '${strings.text('top.account')} · '
              '${strings.text(projection.presenceKey)} · '
              '${gamePresenceLabel(strings, projection)} · '
              '${strings.text(projection.syncKey)}'
        : '${strings.text('top.account')} · $issueTitle · $issueDetail';
    return Semantics(
      container: true,
      liveRegion: issue != null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          key: const Key('account-command'),
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(
              Size(tokens.density.controlHeight, tokens.density.controlHeight),
            ),
            maximumSize: WidgetStatePropertyAll(
              Size(
                expanded
                    ? tokens.density.navigationCompact
                    : tokens.density.controlHeight,
                tokens.density.controlHeight,
              ),
            ),
            padding: WidgetStatePropertyAll(
              expanded
                  ? EdgeInsetsDirectional.fromSTEB(
                      tokens.space.xs,
                      tokens.space.xxs,
                      tokens.space.sm,
                      tokens.space.xxs,
                    )
                  : EdgeInsets.zero,
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: tokens.shape.small),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (menuOpen ||
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return tokens.surfaces.selected.fill;
              }
              if (issueTone != null) {
                return issueTone.background.withValues(alpha: 0.72);
              }
              return tokens.surfaces.chrome.fill;
            }),
            foregroundColor: WidgetStatePropertyAll(tokens.colors.textPrimary),
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
              _AccountAvatar(
                imageData: projection.accountAvatarImageData,
                label: accountLabel,
                signedIn: projection.accountSignedIn,
                loading: accountLoading,
                presenceColor: presenceColor(
                  tokens.colors,
                  projection.displayPresenceKey,
                ),
                issueColor: issueTone?.foreground,
              ),
              if (expanded) ...[
                SizedBox(width: tokens.space.xs),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        issueTitle ?? displayPresenceLabel(strings, projection),
                        key: issue == null
                            ? const Key('account-presence')
                            : const Key('account-status-issue'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              height: 1,
                              color:
                                  issueTone?.foreground ??
                                  presenceColor(
                                    tokens.colors,
                                    projection.displayPresenceKey,
                                  ),
                              fontWeight: issue == null
                                  ? null
                                  : FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: tokens.space.xxs),
                StarBridgeIcon(
                  StarBridgeIconSemantic.menuDown,
                  size: tokens.icons.small,
                  color: issueTone?.foreground ?? tokens.colors.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    this.imageData,
    required this.label,
    required this.signedIn,
    required this.presenceColor,
    this.loading = false,
    this.issueColor,
  });

  final String label;
  final String? imageData;
  final bool signedIn;
  final Color presenceColor;
  final bool loading;
  final Color? issueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasPhoto = signedIn && (imageData?.trim().isNotEmpty ?? false);
    return Container(
      key: const Key('account-avatar-status'),
      clipBehavior: Clip.antiAlias,
      width: tokens.icons.large,
      height: tokens.icons.large,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hasPhoto ? null : tokens.surfaces.raised.fill,
        borderRadius: tokens.shape.small,
        border: hasPhoto
            ? null
            : Border.all(
                color: issueColor ?? presenceColor,
                width: issueColor == null
                    ? tokens.stroke.hairline
                    : tokens.stroke.regular,
              ),
      ),
      child: loading
          ? SizedBox.square(
              dimension: tokens.icons.small,
              child: CircularProgressIndicator(
                key: const Key('account-avatar-loading'),
                strokeWidth: tokens.stroke.strong,
                color: issueColor ?? tokens.colors.info,
              ),
            )
          : signedIn
          ? EmbeddedAvatar(
              source: imageData,
              fallback: Text(
                label.characters.first.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: tokens.colors.textPrimary),
              ),
            )
          : StarBridgeIcon(
              StarBridgeIconSemantic.account,
              size: tokens.icons.small,
              color: tokens.colors.textSecondary,
            ),
    );
  }
}

String _accountDisplayLabel(
  AppStrings strings,
  ShellChromeProjection projection,
) {
  final label = projection.accountLabel.trim();
  if (label.isNotEmpty) {
    return label;
  }
  return strings.text(
    _accountIdentityIsLoading(projection)
        ? 'account.loading'
        : 'account.notSignedIn',
  );
}

bool _accountIdentityIsLoading(ShellChromeProjection projection) =>
    projection.accountBusy &&
    !projection.accountSignedIn &&
    projection.accountLabel.trim().isEmpty;

({Color foreground, Color background}) _accountIssueTone(
  StarBridgeTokens tokens,
  ConnectionIssueProjection issue,
) {
  return switch (issue.state) {
    ConnectionVisualState.normal => (
      foreground: tokens.colors.textSecondary,
      background: tokens.surfaces.status.fill,
    ),
    ConnectionVisualState.pending => (
      foreground: tokens.colors.info,
      background: tokens.colors.infoSoft,
    ),
    ConnectionVisualState.limited || ConnectionVisualState.stale => (
      foreground: tokens.colors.warning,
      background: tokens.colors.warningSoft,
    ),
    ConnectionVisualState.disconnected => (
      foreground: tokens.colors.danger,
      background: tokens.colors.dangerSoft,
    ),
  };
}
