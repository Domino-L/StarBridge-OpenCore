import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../common/user_avatar_menu.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/brand/scm_success_motion.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/embedded_avatar.dart';
import 'account_models.dart';
import 'account_compatibility_card.dart';
import 'account_module.dart';
import 'account_login_dialog.dart';
import 'account_view_components.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/controls/semantic_action_style.dart';
import 'account_operation_motion.dart';
import 'game_identity_verification.dart';
import 'game_identity_verification_dialog.dart';

class AccountSignedInView extends StatelessWidget {
  const AccountSignedInView({
    required this.projection,
    required this.module,
    this.localStatus,
    this.localRecognition,
    this.gameIdentity,
    super.key,
  });

  final AccountProjection projection;
  final AccountModule module;
  final Widget? localStatus;
  final Widget? localRecognition;
  final GameIdentityVerificationPort? gameIdentity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountHeader(projection: projection, module: module),
        SizedBox(height: tokens.space.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >=
                820 * MediaQuery.textScalerOf(context).scale(1);
            final preferences = _ProfilePreferencesCard(
              key: ValueKey((module, projection.generation)),
              projection: projection,
              module: module,
            );
            Widget pair(Widget left, Widget right) => wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      SizedBox(width: tokens.space.md),
                      Expanded(child: right),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      left,
                      SizedBox(height: tokens.space.md),
                      right,
                    ],
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                pair(
                  AccountCompatibilityCard(
                    projection: projection,
                    module: module,
                    existingAccountOnly: true,
                  ),
                  _IdentityCard(
                    identity: projection.identity,
                    module: module,
                    generation: projection.generation,
                    verification: gameIdentity,
                  ),
                ),
                SizedBox(height: tokens.space.md),
                preferences,
                if (localStatus != null || localRecognition != null) ...[
                  SizedBox(height: tokens.space.md),
                  if (localStatus != null && localRecognition != null)
                    pair(localStatus!, localRecognition!)
                  else
                    (localStatus ?? localRecognition)!,
                ],
                // Compatibility binding is available; profile import is not
                // exposed in this release, even when a backend port exists.
                SizedBox(height: tokens.space.md),
                _SessionCard(projection: projection, module: module),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.projection, required this.module});

  final AccountProjection projection;
  final AccountModule module;

  @override
  Widget build(BuildContext context) {
    final profile = projection.profile;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final displayName = profile?.displayName?.trim().isNotEmpty == true
        ? profile!.displayName!.trim()
        : strings.text('account.value.notSet');
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            children: [
              Container(
                width: tokens.density.controlHeight * 1.35,
                height: tokens.density.controlHeight * 1.35,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: tokens.colors.accentSoft,
                  borderRadius: tokens.shape.medium,
                  border: Border.all(
                    color: tokens.colors.accent,
                    width: tokens.stroke.hairline,
                  ),
                ),
                child: UserAvatarMenu(
                  name: displayName,
                  isSelf: true,
                  child: EmbeddedAvatar(
                    source: profile?.avatarImageData,
                    fallback: Text(
                      displayName.characters.first.toUpperCase(),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: tokens.colors.accent),
                    ),
                  ),
                ),
              ),
              SizedBox(width: tokens.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      profile?.email ?? strings.text('account.email.notShared'),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          );
          final refresh = StarBridgeIconAction(
            controlKey: const Key('account-refresh'),
            onActivate: projection.isBusy
                ? null
                : (source) {
                    if (module.projection.value.isBusy) return;
                    unawaited(
                      runAccountMotionCommand(
                        module,
                        AccountOperation.refreshing,
                        source,
                        module.refresh,
                      ),
                    );
                  },
            label: strings.text('account.action.refresh'),
            icon: StarBridgeIcon(StarBridgeIconSemantic.refresh),
          );
          if (constraints.maxWidth <
              640 * MediaQuery.textScalerOf(context).scale(1)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                _ScmLoginBrand(
                  module: module,
                  key: const ValueKey('account-page-brand'),
                ),
                SizedBox(height: tokens.space.sm),
                Row(
                  children: [
                    Expanded(
                      child: AccountFreshnessBadge(
                        freshness: projection.profileFreshness,
                      ),
                    ),
                    SizedBox(width: tokens.space.sm),
                    refresh,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              _ScmLoginBrand(
                module: module,
                key: const ValueKey('account-page-brand'),
              ),
              SizedBox(width: tokens.space.sm),
              AccountFreshnessBadge(freshness: projection.profileFreshness),
              SizedBox(width: tokens.space.sm),
              refresh,
            ],
          );
        },
      ),
    );
  }
}

class _ScmLoginBrand extends StatefulWidget {
  const _ScmLoginBrand({required this.module, super.key});
  final AccountModule module;
  @override
  State<_ScmLoginBrand> createState() => _ScmLoginBrandState();
}

class _ScmLoginBrandState extends State<_ScmLoginBrand> {
  late final bool _play = !isAccountLoginDialogOpen(widget.module);
  @override
  Widget build(BuildContext context) => ScmSuccessMotion(
    key: const Key('scm-account-brand'),
    play: _play,
    brief: true,
  );
}

class _ProfilePreferencesCard extends StatefulWidget {
  const _ProfilePreferencesCard({
    required this.projection,
    required this.module,
    super.key,
  });

  final AccountProjection projection;
  final AccountModule module;

  @override
  State<_ProfilePreferencesCard> createState() =>
      _ProfilePreferencesCardState();
}

class _ProfilePreferencesCardState extends State<_ProfilePreferencesCard> {
  String get _locale => widget.module.preferencesDraft.locale;
  String get _timeZone => widget.module.preferencesDraft.timeZone;

  @override
  void initState() {
    super.initState();
    widget.module.preferencesDraft.addListener(_draftChanged);
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.module.preferencesDraft.removeListener(_draftChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final owner = widget.module;
    final editable = widget.projection.canEditPreferences;
    final localeValues = <String>{
      '',
      ...widget.projection.localeOptions,
      if (_locale.isNotEmpty) _locale,
    };
    final zones = <String, AccountTimeZoneOption>{
      for (final zone in widget.projection.timeZoneOptions) zone.value: zone,
    };
    if (_timeZone.isNotEmpty && !zones.containsKey(_timeZone)) {
      zones[_timeZone] = AccountTimeZoneOption(
        value: _timeZone,
        label: _timeZone,
        offset: '',
      );
    }
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccountCardHeading(
            semantic: StarBridgeIconSemantic.profile,
            titleKey: 'account.preferences.title',
            bodyKey: 'account.preferences.body',
          ),
          SizedBox(height: tokens.space.lg),
          if (!widget.projection.supportsPreferenceWrite) ...[
            Text(strings.text('account.preferences.readOnly')),
            SizedBox(height: tokens.space.md),
          ],
          if (widget.projection.operation ==
              AccountOperation.savingPreferences) ...[
            Text(strings.text('account.preferences.authorizing')),
            SizedBox(height: tokens.space.md),
          ],
          if (widget.projection.profileFreshness ==
              AccountProfileFreshness.cached) ...[
            AccountInlineNotice(
              icon: StarBridgeIconSemantic.cache,
              textKey: 'account.preferences.cachedReadOnly',
              color: tokens.colors.warning,
              background: tokens.colors.warningSoft,
            ),
            SizedBox(height: tokens.space.md),
          ],
          StarBridgeSelectFormField<String>(
            identity: 'account-locale',
            controlKey: const Key('account-locale-control'),
            key: const Key('account-locale-field'),
            initialValue: _locale,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: strings.text('account.preferences.locale'),
            ),
            items: localeValues
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(
                      _localeLabel(strings, value),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: editable
                ? (value) =>
                      widget.module.preferencesDraft.setLocale(value ?? '')
                : null,
          ),
          SizedBox(height: tokens.space.md),
          StarBridgeSelectFormField<String>(
            identity: 'account-time-zone',
            controlKey: const Key('account-time-zone-control'),
            key: const Key('account-time-zone-field'),
            initialValue: _timeZone,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: strings.text('account.preferences.timeZone'),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(strings.text('account.value.notSet')),
              ),
              ...zones.values.map(
                (zone) => DropdownMenuItem(
                  value: zone.value,
                  child: Text(
                    zone.offset.isEmpty
                        ? zone.label
                        : '(${zone.offset}) ${zone.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: editable
                ? (value) =>
                      widget.module.preferencesDraft.setTimeZone(value ?? '')
                : null,
          ),
          SizedBox(height: tokens.space.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              controlKey: const Key('account-save-preferences'),
              onActivate: editable
                  ? (source) {
                      if (!mounted ||
                          !identical(owner, widget.module) ||
                          !owner.projection.value.canEditPreferences) {
                        return;
                      }
                      unawaited(
                        runAccountMotionCommand(
                          owner,
                          AccountOperation.savingPreferences,
                          source,
                          () => owner.savePreferences(
                            locale: _locale.isEmpty ? null : _locale,
                            timeZone: _timeZone.isEmpty ? null : _timeZone,
                          ),
                        ),
                      );
                    }
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.projection.operation ==
                          AccountOperation.savingPreferences
                      ? SizedBox.square(
                          dimension: 16,
                          child: AccountOperationWaiting(module: owner),
                        )
                      : StarBridgeIcon(StarBridgeIconSemantic.save),
                  SizedBox(width: tokens.space.xs),
                  Flexible(
                    child: Text(
                      strings.text(
                        widget.projection.operation ==
                                AccountOperation.savingPreferences
                            ? 'account.preferences.saving'
                            : 'account.preferences.save',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.module.preferencesDraft.hasChanges) ...[
            SizedBox(height: tokens.space.sm),
            Text(
              strings.text('account.preferences.draft'),
              key: const Key('account-preferences-unsaved'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('account-preferences-discard'),
                onActivate: widget.projection.isBusy
                    ? null
                    : (_) {
                        if (!mounted ||
                            !identical(owner, widget.module) ||
                            owner.projection.value.isBusy) {
                          return;
                        }
                        owner.preferencesDraft.discard();
                      },
                child: Text(strings.text('account.preferences.discard')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _localeLabel(AppStrings strings, String value) {
    return switch (value) {
      '' => strings.text('account.value.notSet'),
      'zh-CN' => strings.text('account.locale.zhCN'),
      'en-US' => strings.text('account.locale.enUS'),
      _ => value,
    };
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.identity,
    required this.module,
    required this.generation,
    this.verification,
  });

  final AccountIdentityProjection identity;
  final AccountModule module;
  final int? generation;
  final GameIdentityVerificationPort? verification;

  bool get _canVerify =>
      verification?.supportsGameIdentityVerification == true &&
      const {
        AccountIdentityState.verificationRequired,
        AccountIdentityState.reverifyRequired,
        AccountIdentityState.revoked,
      }.contains(identity.state);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final presentation = accountIdentityPresentation(identity.state, tokens);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountCardHeading(
            semantic: presentation.icon,
            titleKey: 'account.identity.title',
            bodyKey: presentation.bodyKey,
            color: presentation.color,
          ),
          if (identity.authoritativeHandle case final handle?) ...[
            SizedBox(height: tokens.space.md),
            AccountLabelValue(
              label: strings.text('account.identity.handle'),
              value: handle,
            ),
          ],
          SizedBox(height: tokens.space.md),
          AccountInlineNotice(
            icon: identity.sensitiveWritesAllowed
                ? StarBridgeIconSemantic.connected
                : StarBridgeIconSemantic.warning,
            textKey: identity.sensitiveWritesAllowed
                ? 'account.identity.writesAllowed'
                : 'account.identity.writesBlocked',
            color: identity.sensitiveWritesAllowed
                ? tokens.colors.success
                : presentation.color,
            background: identity.sensitiveWritesAllowed
                ? tokens.colors.successSoft
                : presentation.background,
          ),
          if (verification case final port?)
            StreamBuilder<void>(
              stream: port.supportChanges,
              builder: (context, _) => !_canVerify
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.only(top: tokens.space.md),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StarBridgeActionButton(
                          kind: StarBridgeActionKind.primary,
                          controlKey: const Key('account-verify-game-identity'),
                          onActivate: (source) => unawaited(
                            showGameIdentityVerificationDialog(
                              context,
                              port,
                              initialHandle: identity.detectedHandle,
                              source: source,
                              isCurrent: () =>
                                  module.projection.value.generation ==
                                  generation,
                              ownerChanges: module.projection,
                              onVerified: () => unawaited(module.refresh()),
                            ),
                          ),
                          child: Text(
                            strings.text('account.gameIdentity.action'),
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.projection, required this.module});

  final AccountProjection projection;
  final AccountModule module;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final clearing = projection.operation == AccountOperation.clearingCache;
    final signingOut = projection.operation == AccountOperation.signingOut;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccountCardHeading(
            semantic: StarBridgeIconSemantic.cache,
            titleKey: 'account.session.title',
            bodyKey: 'account.session.body',
          ),
          SizedBox(height: tokens.space.md),
          StarBridgeActionButton(
            controlKey: const Key('account-clear-cache'),
            onActivate: projection.canClearProfileCache
                ? (source) => unawaited(
                    runAccountMotionCommand(
                      module,
                      AccountOperation.clearingCache,
                      source,
                      module.clearLocalCache,
                    ),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (clearing)
                  SizedBox(
                    width: 40,
                    child: AccountOperationWaiting(module: module),
                  )
                else
                  StarBridgeIcon(StarBridgeIconSemantic.cache),
                SizedBox(width: tokens.space.xs),
                Flexible(
                  child: Text(
                    strings.text(
                      clearing
                          ? 'account.cache.clearing'
                          : 'account.cache.clear',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!projection.supportsCacheClear) ...[
            SizedBox(height: tokens.space.sm),
            Text(strings.text('account.action.unavailable')),
          ],
          SizedBox(height: tokens.space.sm),
          StarBridgeActionButton(
            controlKey: const Key('account-logout'),
            tone: ActionTone.danger,
            onActivate: projection.canLogout
                ? (source) => unawaited(
                    runAccountMotionCommand(
                      module,
                      AccountOperation.signingOut,
                      source,
                      module.logout,
                    ),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StarBridgeIcon(StarBridgeIconSemantic.logout),
                SizedBox(width: tokens.space.xs),
                Flexible(
                  child: Text(
                    strings.text(
                      signingOut
                          ? 'account.logout.signingOut'
                          : 'account.logout.action',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
