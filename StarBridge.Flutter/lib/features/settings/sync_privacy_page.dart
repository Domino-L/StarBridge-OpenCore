import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'direct_message_privacy_module.dart';
import 'direct_message_privacy_setting.dart';
import 'friend_request_privacy_module.dart';
import 'friend_request_privacy_setting.dart';
import 'recently_played_privacy_module.dart';
import 'recently_played_privacy_setting.dart';
import 'sync_privacy_models.dart';
import 'sync_privacy_module.dart';
import 'sync_privacy_page_components.dart';
import 'privacy_page_drafts.dart';

class SyncPrivacyPage extends StatelessWidget {
  const SyncPrivacyPage({
    required this.module,
    this.directMessagePrivacy,
    this.friendRequestPrivacy,
    this.recentlyPlayedPrivacy,
    this.showLegacyEvents = true,
    this.friendSharing,
    this.gameIdVisibility,
    super.key,
  });

  final SyncPrivacyModule module;
  final Widget? friendSharing;
  final Widget? gameIdVisibility;
  final bool showLegacyEvents;
  final DirectMessagePrivacyModule? directMessagePrivacy;
  final FriendRequestPrivacyModule? friendRequestPrivacy;
  final RecentlyPlayedPrivacyModule? recentlyPlayedPrivacy;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncPrivacyProjection>(
      valueListenable: module.projection,
      builder: (context, projection, _) => switch (projection.availability) {
        SyncPrivacyAvailability.loading => const SyncPrivacyLoadingView(),
        SyncPrivacyAvailability.signedOut => const SyncPrivacyStateView(
          key: Key('sync-privacy-signed-out'),
          icon: StarBridgeIconSemantic.login,
          titleKey: 'settings.privacy.signedOut.title',
          bodyKey: 'settings.privacy.signedOut.body',
        ),
        SyncPrivacyAvailability.unavailable => _SyncPrivacyUnavailableOverview(
          friendSharing: friendSharing,
          gameIdVisibility: gameIdVisibility,
          showLegacyEvents: showLegacyEvents,
          module: module,
          failure: projection.failure,
          directMessagePrivacy: directMessagePrivacy,
          friendRequestPrivacy: friendRequestPrivacy,
          recentlyPlayedPrivacy: recentlyPlayedPrivacy,
        ),
        SyncPrivacyAvailability.available => _SyncPrivacyContent(
          showLegacyEvents: showLegacyEvents,
          module: module,
          projection: projection,
          directMessagePrivacy: directMessagePrivacy,
          friendRequestPrivacy: friendRequestPrivacy,
          recentlyPlayedPrivacy: recentlyPlayedPrivacy,
        ),
      },
    );
  }
}

String _failureKey(SyncPrivacyFailure? failure) => switch (failure) {
  SyncPrivacyFailure.hostUnavailable =>
    'settings.privacy.error.hostUnavailable',
  SyncPrivacyFailure.readFailed => 'settings.privacy.error.readFailed',
  SyncPrivacyFailure.writeFailed => 'settings.privacy.error.writeFailed',
  SyncPrivacyFailure.writeConflict => 'settings.privacy.error.writeConflict',
  SyncPrivacyFailure.invalidResponse =>
    'settings.privacy.error.invalidResponse',
  null => 'settings.privacy.error.unavailable',
};

class _SyncPrivacyUnavailableOverview extends StatelessWidget {
  const _SyncPrivacyUnavailableOverview({
    this.friendSharing,
    this.gameIdVisibility,
    required this.showLegacyEvents,
    required this.module,
    required this.failure,
    required this.directMessagePrivacy,
    required this.friendRequestPrivacy,
    required this.recentlyPlayedPrivacy,
  });

  final SyncPrivacyModule module;
  final SyncPrivacyFailure? failure;
  final Widget? friendSharing;
  final Widget? gameIdVisibility;
  final bool showLegacyEvents;
  final DirectMessagePrivacyModule? directMessagePrivacy;
  final FriendRequestPrivacyModule? friendRequestPrivacy;
  final RecentlyPlayedPrivacyModule? recentlyPlayedPrivacy;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SingleChildScrollView(
      key: const Key('sync-privacy-unavailable'),
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        tokens.space.xxl,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('settings.privacy.title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                strings.text('settings.privacy.description'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              SizedBox(height: tokens.space.md),
              if (friendSharing == null)
                SyncPrivacyFailureBanner(
                  messageKey: _failureKey(failure),
                  onRetry: module.refresh,
                ),
              SizedBox(height: tokens.space.md),
              friendSharing ??
                  _UnavailableSettingsGroup(
                    icon: StarBridgeIconSemantic.friends,
                    titleKey: 'settings.privacy.friends.title',
                    descriptionKey: 'settings.privacy.friends.description',
                    itemKeys: const [
                      'settings.privacy.field.presence',
                      'settings.privacy.field.serverRelation',
                      'settings.privacy.field.serverDetails',
                      'settings.privacy.field.ship',
                      'settings.privacy.field.location',
                      'settings.privacy.field.lastOnline',
                    ],
                  ),
              SizedBox(height: tokens.space.md),
              if (showLegacyEvents)
                _UnavailableSettingsGroup(
                  icon: StarBridgeIconSemantic.activity,
                  titleKey: 'settings.privacy.events.title',
                  descriptionKey: 'settings.privacy.events.description',
                  itemKeys: const [
                    'settings.privacy.events.presence',
                    'settings.privacy.events.server',
                    'settings.privacy.events.ship',
                    'settings.privacy.events.location',
                    'settings.privacy.events.life',
                  ],
                ),
              SizedBox(height: tokens.space.md),
              if (gameIdVisibility != null) ...[
                gameIdVisibility!,
                SizedBox(height: tokens.space.md),
              ],
              _UnavailableSettingsGroup(
                icon: StarBridgeIconSemantic.privacy,
                titleKey: 'settings.privacy.social.title',
                descriptionKey: 'settings.privacy.social.description',
                itemKeys: const [],
                footer: Column(
                  children: [
                    FriendRequestPrivacySetting(module: friendRequestPrivacy),
                    const Divider(height: 1),
                    DirectMessagePrivacySetting(module: directMessagePrivacy),
                    const Divider(height: 1),
                    RecentlyPlayedPrivacySetting(module: recentlyPlayedPrivacy),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableSettingsGroup extends StatelessWidget {
  const _UnavailableSettingsGroup({
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
    required this.itemKeys,
    this.footer,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String descriptionKey;
  final List<String> itemKeys;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SyncPrivacySettingsPanel(
      icon: icon,
      titleKey: titleKey,
      descriptionKey: descriptionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: tokens.space.xs,
            runSpacing: tokens.space.xs,
            children: [
              for (final key in itemKeys)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space.sm,
                    vertical: tokens.space.xs,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaces.panel.fill,
                    border: Border.all(
                      color: tokens.surfaces.panel.border,
                      width: tokens.stroke.hairline,
                    ),
                    borderRadius: tokens.shape.small,
                  ),
                  child: Text(
                    '${strings.text(key)} · ${strings.text('settings.privacy.unavailable.value')}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ),
            ],
          ),
          if (footer != null) ...[SizedBox(height: tokens.space.sm), footer!],
        ],
      ),
    );
  }
}

class _SyncPrivacyContent extends StatelessWidget {
  const _SyncPrivacyContent({
    required this.showLegacyEvents,
    required this.module,
    required this.projection,
    required this.directMessagePrivacy,
    required this.friendRequestPrivacy,
    required this.recentlyPlayedPrivacy,
  });

  final SyncPrivacyModule module;
  final SyncPrivacyProjection projection;
  final bool showLegacyEvents;
  final DirectMessagePrivacyModule? directMessagePrivacy;
  final FriendRequestPrivacyModule? friendRequestPrivacy;
  final RecentlyPlayedPrivacyModule? recentlyPlayedPrivacy;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final drafts = PrivacyDraftScope.of(context);
    final settings =
        drafts?.value('sync-settings', projection.settings!) ??
        projection.settings!;
    final enabled = projection.canEdit && !(drafts?.saving ?? false);
    Future<bool> save(SyncPrivacySettingsValue value) async {
      if (drafts == null) return module.save(value);
      drafts.edit('sync-settings', projection.settings!, value, module.save);
      return true;
    }

    return SingleChildScrollView(
      key: const Key('sync-privacy-content'),
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        tokens.space.xxl,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('settings.privacy.title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                strings.text('settings.privacy.description'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              if (projection.operation == SyncPrivacyOperation.saving) ...[
                SizedBox(height: tokens.space.md),
                const LinearProgressIndicator(key: Key('sync-privacy-saving')),
              ],
              if (projection.failure case final failure?) ...[
                SizedBox(height: tokens.space.md),
                SyncPrivacyFailureBanner(
                  messageKey: _failureKey(failure),
                  onRetry: module.refresh,
                ),
              ],
              SizedBox(height: tokens.space.lg),
              SyncPrivacyVisibilityMap(settings: settings),
              SizedBox(height: tokens.space.md),
              SyncPrivacySettingsPanel(
                icon: StarBridgeIconSemantic.connected,
                titleKey: 'settings.privacy.realtime.title',
                descriptionKey: 'settings.privacy.realtime.description',
                sourceKey: 'settings.privacy.source.account',
                child: SyncPrivacySettingRow(
                  settingKey: const Key('privacy-realtime-sync'),
                  titleKey: 'settings.privacy.realtime.enabled',
                  descriptionKey: settings.hasActiveCollaboration
                      ? 'settings.privacy.realtime.activeContext'
                      : 'settings.privacy.realtime.enabledDescription',
                  value: settings.realtimeSyncEnabled,
                  enabled: enabled,
                  onChanged: (value) async {
                    if (!value &&
                        !await confirmRealtimePause(
                          context,
                          hasActiveCollaboration:
                              settings.hasActiveCollaboration,
                        )) {
                      return false;
                    }
                    return save(settings.copyWith(realtimeSyncEnabled: value));
                  },
                ),
              ),
              SizedBox(height: tokens.space.md),
              SyncPrivacySettingsPanel(
                icon: StarBridgeIconSemantic.friends,
                titleKey: 'settings.privacy.friends.title',
                descriptionKey: 'settings.privacy.friends.description',
                sourceKey: 'settings.privacy.source.account',
                child: Column(
                  children: [
                    SyncPrivacySettingRow(
                      settingKey: const Key('privacy-friends-presence'),
                      titleKey: 'settings.privacy.field.presence',
                      descriptionKey:
                          'settings.privacy.field.presenceDescription',
                      value: settings.friendDefaults.presence,
                      enabled: enabled,
                      onChanged: (value) => save(
                        settings.copyWith(
                          friendDefaults: settings.friendDefaults.copyWith(
                            presence: value,
                          ),
                        ),
                      ),
                    ),
                    SyncPrivacySettingRow(
                      settingKey: const Key('privacy-friends-server-relation'),
                      titleKey: 'settings.privacy.field.serverRelation',
                      descriptionKey:
                          'settings.privacy.field.serverRelationDescription',
                      value: settings.friendDefaults.serverRelation,
                      enabled: enabled,
                      onChanged: (value) => save(
                        settings.copyWith(
                          friendDefaults: settings.friendDefaults.copyWith(
                            serverRelation: value,
                          ),
                        ),
                      ),
                    ),
                    SyncPrivacySettingRow(
                      settingKey: const Key('privacy-friends-server-details'),
                      titleKey: 'settings.privacy.field.serverDetails',
                      descriptionKey:
                          'settings.privacy.field.serverDetailsDescription',
                      value: settings.friendDefaults.serverDetails,
                      enabled: enabled,
                      onChanged: (value) => save(
                        settings.copyWith(
                          friendDefaults: settings.friendDefaults.copyWith(
                            serverDetails: value,
                          ),
                        ),
                      ),
                    ),
                    SyncPrivacySettingRow(
                      settingKey: const Key('privacy-friends-ship'),
                      titleKey: 'settings.privacy.field.ship',
                      descriptionKey: 'settings.privacy.field.shipDescription',
                      value: settings.friendDefaults.ship,
                      enabled: enabled,
                      onChanged: (value) => save(
                        settings.copyWith(
                          friendDefaults: settings.friendDefaults.copyWith(
                            ship: value,
                          ),
                        ),
                      ),
                    ),
                    SyncPrivacySettingRow(
                      settingKey: const Key('privacy-friends-location'),
                      titleKey: 'settings.privacy.field.location',
                      descriptionKey:
                          'settings.privacy.field.locationDescription',
                      value: settings.friendDefaults.location,
                      enabled: enabled,
                      onChanged: (value) => save(
                        settings.copyWith(
                          friendDefaults: settings.friendDefaults.copyWith(
                            location: value,
                          ),
                        ),
                      ),
                    ),
                    SyncPrivacySettingRow(
                      settingKey: const Key('privacy-friends-last-online'),
                      titleKey: 'settings.privacy.field.lastOnline',
                      descriptionKey:
                          'settings.privacy.field.lastOnlineDescription',
                      value: settings.friendDefaults.lastOnline,
                      enabled: enabled,
                      onChanged: (value) => save(
                        settings.copyWith(
                          friendDefaults: settings.friendDefaults.copyWith(
                            lastOnline: value,
                          ),
                        ),
                      ),
                      showDivider: false,
                    ),
                    SizedBox(height: tokens.space.sm),
                    const SyncPrivacyBoundaryNote(
                      icon: StarBridgeIconSemantic.account,
                      titleKey: 'settings.privacy.friendExceptions.title',
                      bodyKey: 'settings.privacy.friendExceptions.body',
                    ),
                  ],
                ),
              ),
              SizedBox(height: tokens.space.md),
              if (showLegacyEvents)
                SyncPrivacySettingsPanel(
                  icon: StarBridgeIconSemantic.activity,
                  titleKey: 'settings.privacy.events.title',
                  descriptionKey: 'settings.privacy.events.description',
                  sourceKey: 'settings.privacy.source.account',
                  child: Column(
                    children: [
                      SyncPrivacySettingRow(
                        settingKey: const Key('privacy-events-enabled'),
                        titleKey: 'settings.privacy.events.enabled',
                        descriptionKey:
                            'settings.privacy.events.enabledDescription',
                        value: settings.eventSharing.enabled,
                        enabled: enabled,
                        onChanged: (value) => save(
                          settings.copyWith(
                            eventSharing: settings.eventSharing.copyWith(
                              enabled: value,
                            ),
                          ),
                        ),
                      ),
                      SyncPrivacyEventChoices(
                        settings: settings,
                        enabled: enabled && settings.eventSharing.enabled,
                        onSave: save,
                      ),
                    ],
                  ),
                ),
              SizedBox(height: tokens.space.md),
              SyncPrivacySettingsPanel(
                icon: StarBridgeIconSemantic.privacy,
                titleKey: 'settings.privacy.social.title',
                descriptionKey: 'settings.privacy.social.description',
                sourceKey: 'settings.privacy.source.account',
                child: Column(
                  children: [
                    FriendRequestPrivacySetting(module: friendRequestPrivacy),
                    const Divider(height: 1),
                    DirectMessagePrivacySetting(module: directMessagePrivacy),
                    const Divider(height: 1),
                    RecentlyPlayedPrivacySetting(module: recentlyPlayedPrivacy),
                    const Divider(height: 1),
                    SyncPrivacySettingRow(
                      settingKey: const Key('privacy-low-confidence-location'),
                      titleKey: 'settings.privacy.social.lowConfidence',
                      descriptionKey:
                          'settings.privacy.social.lowConfidenceDescription',
                      value: settings.social.hideLowConfidenceLocation,
                      enabled: enabled,
                      onChanged: (value) => save(
                        settings.copyWith(
                          social: settings.social.copyWith(
                            hideLowConfidenceLocation: value,
                          ),
                        ),
                      ),
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              SizedBox(height: tokens.space.md),
              SyncPrivacySettingsPanel(
                icon: StarBridgeIconSemantic.room,
                titleKey: 'settings.privacy.boundaries.title',
                descriptionKey: 'settings.privacy.boundaries.description',
                child: Column(
                  children: [
                    const SyncPrivacyBoundaryNote(
                      icon: StarBridgeIconSemantic.operation,
                      titleKey: 'settings.privacy.context.title',
                      bodyKey: 'settings.privacy.context.body',
                    ),
                    SizedBox(height: tokens.space.sm),
                    const SyncPrivacyBoundaryNote(
                      icon: StarBridgeIconSemantic.hangar,
                      titleKey: 'settings.privacy.hangar.title',
                      bodyKey: 'settings.privacy.hangar.body',
                    ),
                  ],
                ),
              ),
              SizedBox(height: tokens.space.md),
              Text(
                strings.text('settings.privacy.authorityNotice'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
