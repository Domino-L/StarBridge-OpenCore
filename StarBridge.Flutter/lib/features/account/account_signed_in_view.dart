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
import 'account_compatibility_card.dart';
import 'account_module.dart';
import 'account_view_components.dart';
import 'legacy_profile_migration_card.dart';

class AccountSignedInView extends StatelessWidget {
  const AccountSignedInView({
    required this.projection,
    required this.module,
    this.localStatus,
    super.key,
  });

  final AccountProjection projection;
  final AccountModule module;
  final Widget? localStatus;

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
            final wide = constraints.maxWidth >= 820;
            final preferences = _ProfilePreferencesCard(
              key: ValueKey(projection.generation),
              projection: projection,
              module: module,
            );
            final primary = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                preferences,
                if (localStatus case final status?) ...[
                  SizedBox(height: tokens.space.md),
                  status,
                ],
              ],
            );
            final side = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IdentityCard(identity: projection.identity),
                SizedBox(height: tokens.space.md),
                AccountCompatibilityCard(
                  projection: projection,
                  module: module,
                  existingAccountOnly: true,
                ),
                if (module.legacyMigration case final migration?) ...[
                  SizedBox(height: tokens.space.md),
                  LegacyProfileMigrationCard(
                    key: ValueKey('legacy-migration-${projection.generation}'),
                    port: migration,
                  ),
                ],
                SizedBox(height: tokens.space.md),
                _SessionCard(projection: projection, module: module),
              ],
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primary,
                  SizedBox(height: tokens.space.md),
                  side,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: primary),
                SizedBox(width: tokens.space.md),
                Expanded(flex: 2, child: side),
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
                child: UserAvatarMenu(name: displayName, isSelf: true, child: EmbeddedAvatar(
                  source: profile?.avatarImageData,
                  fallback: Text(
                    displayName.characters.first.toUpperCase(),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: tokens.colors.accent),
                  ),
                )),
              ),
              SizedBox(width: tokens.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      profile?.email ?? strings.text('account.email.notShared'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                    SizedBox(height: tokens.space.xs),
                    const ScmBrandMark.compact(key: Key('scm-account-brand')),
                  ],
                ),
              ),
            ],
          );
          final refresh = IconButton(
            key: const Key('account-refresh'),
            onPressed: projection.isBusy
                ? null
                : () => unawaited(module.refresh()),
            tooltip: strings.text('account.action.refresh'),
            icon: StarBridgeIcon(StarBridgeIconSemantic.refresh),
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
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
              SizedBox(width: tokens.space.sm),
              Flexible(
                child: AccountFreshnessBadge(
                  freshness: projection.profileFreshness,
                ),
              ),
              SizedBox(width: tokens.space.sm),
              refresh,
            ],
          );
        },
      ),
    );
  }
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
          DropdownButtonFormField<String>(
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
          DropdownButtonFormField<String>(
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
            child: FilledButton.icon(
              key: const Key('account-save-preferences'),
              onPressed: editable
                  ? () => unawaited(
                      widget.module.savePreferences(
                        locale: _locale.isEmpty ? null : _locale,
                        timeZone: _timeZone.isEmpty ? null : _timeZone,
                      ),
                    )
                  : null,
              icon:
                  widget.projection.operation ==
                      AccountOperation.savingPreferences
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : StarBridgeIcon(StarBridgeIconSemantic.save),
              label: Text(
                strings.text(
                  widget.projection.operation ==
                          AccountOperation.savingPreferences
                      ? 'account.preferences.saving'
                      : 'account.preferences.save',
                ),
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
              child: TextButton(
                key: const Key('account-preferences-discard'),
                onPressed: widget.projection.isBusy
                    ? null
                    : widget.module.preferencesDraft.discard,
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
  const _IdentityCard({required this.identity});

  final AccountIdentityProjection identity;

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
          OutlinedButton.icon(
            key: const Key('account-clear-cache'),
            onPressed: projection.canClearProfileCache
                ? () => unawaited(module.clearLocalCache())
                : null,
            icon: clearing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : StarBridgeIcon(StarBridgeIconSemantic.cache),
            label: Text(
              strings.text(
                clearing ? 'account.cache.clearing' : 'account.cache.clear',
              ),
            ),
          ),
          if (!projection.supportsCacheClear) ...[
            SizedBox(height: tokens.space.sm),
            Text(strings.text('account.action.unavailable')),
          ],
          SizedBox(height: tokens.space.sm),
          OutlinedButton.icon(
            key: const Key('account-logout'),
            onPressed: projection.canLogout
                ? () => unawaited(module.logout())
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.colors.danger,
              side: BorderSide(
                color: tokens.colors.danger,
                width: tokens.stroke.regular,
              ),
            ),
            icon: StarBridgeIcon(StarBridgeIconSemantic.logout),
            label: Text(
              strings.text(
                signingOut
                    ? 'account.logout.signingOut'
                    : 'account.logout.action',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
