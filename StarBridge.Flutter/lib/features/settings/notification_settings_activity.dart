import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'notification_settings_common.dart';
import 'notification_settings_models.dart';

class PlayerActivityNotificationPanel extends StatelessWidget {
  const PlayerActivityNotificationPanel({
    required this.settings,
    required this.enabled,
    required this.onSave,
    this.communityAudienceLabel,
    super.key,
  });

  final String? communityAudienceLabel;
  final NotificationSettingsValue settings;
  final bool enabled;
  final Future<bool> Function(NotificationSettingsValue settings) onSave;

  @override
  Widget build(BuildContext context) {
    final activity = settings.playerActivity;
    final tokens = context.tokens;
    final locale = Localizations.localeOf(context);
    final en = locale.languageCode == 'en';
    final tw = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
    return NotificationSettingsPanel(
      key: const Key('notification-player-activity-panel'),
      icon: StarBridgeIconSemantic.activity,
      titleKey: 'settings.notification.activity.title',
      descriptionKey: 'settings.notification.activity.description',
      accentColor: tokens.colors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              key: const Key('player-activity-card-preview'),
              width: 344,
              padding: EdgeInsets.all(tokens.space.md),
              decoration: BoxDecoration(
                color: tokens.surfaces.ground.fill,
                gradient: LinearGradient(
                  colors: [
                    tokens.colors.success,
                    tokens.colors.success,
                    tokens.surfaces.ground.fill,
                    tokens.surfaces.ground.fill,
                  ],
                  stops: const [0, 0.009, 0.009, 1],
                ),
                borderRadius: tokens.shape.small,
                border: Border.all(color: tokens.surfaces.panel.border),
              ),
              child: Row(
                children: [
                  StarBridgeIcon(
                    StarBridgeIconSemantic.friends,
                    size: 36,
                    color: tokens.colors.textSecondary,
                  ),
                  SizedBox(width: tokens.space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          en
                              ? 'Test player'
                              : tw
                              ? '測試玩家'
                              : '测试玩家',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          en
                              ? 'Started playing Star Citizen'
                              : tw
                              ? '開始遊玩 Star Citizen'
                              : '开始游玩 Star Citizen',
                          style: TextStyle(color: tokens.colors.success),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          en
                              ? 'Friend · Example Fleet member · Same room'
                              : tw
                              ? '好友 · 範例組織成員 · 同房間'
                              : '好友 · 示例组织成员 · 同房间',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: tokens.space.sm),
          Text(
            en
                ? 'Example only. Activity cards disappear automatically without interrupting your controls.'
                : tw
                ? '此為顯示範例。玩家卡片會自動消失，不攔截滑鼠操作。'
                : '仅为显示示例。玩家卡片自动消失，不拦截鼠标操作。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          NotificationToggleRow(
            settingKey: const Key('notification-player-activity-enabled'),
            titleKey: 'settings.notification.activity.enabled.title',
            descriptionKey:
                'settings.notification.activity.enabled.description',
            value: activity.enabled,
            enabled: enabled,
            onChanged: (value) => onSave(
              settings.copyWith(
                playerActivity: activity.copyWith(enabled: value),
              ),
            ),
            showDivider: false,
            badgeKey: 'settings.notification.scope.device',
          ),
          SizedBox(height: tokens.space.sm),
          _ActivityGroup(
            titleKey: 'settings.notification.activity.audiences.title',
            descriptionKey:
                'settings.notification.activity.audiences.description',
            child: _ToggleGrid(
              children: [
                _CompactToggle(
                  settingKey: const Key('notification-activity-fleet'),
                  icon: StarBridgeIconSemantic.officialFleet,
                  titleKey:
                      'settings.notification.activity.audience.officialFleet',
                  titleOverride: communityAudienceLabel,
                  value: activity.includeOfficialFleet,
                  enabled: enabled && activity.enabled,
                  color: tokens.domainColors
                      .resolve(DomainColorRole.command)
                      .foreground,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(
                        includeOfficialFleet: value,
                      ),
                    ),
                  ),
                ),
                _CompactToggle(
                  settingKey: const Key('notification-activity-friends'),
                  icon: StarBridgeIconSemantic.friends,
                  titleKey: 'settings.notification.activity.audience.friends',
                  value: activity.includeFriends,
                  enabled: enabled && activity.enabled,
                  color: tokens.colors.info,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(includeFriends: value),
                    ),
                  ),
                ),
                _CompactToggle(
                  settingKey: const Key('notification-activity-room'),
                  icon: StarBridgeIconSemantic.room,
                  titleKey: 'settings.notification.activity.audience.room',
                  value: activity.includeCurrentRoom,
                  enabled: enabled && activity.enabled,
                  color: tokens.colors.success,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(
                        includeCurrentRoom: value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.space.sm),
          _ActivityGroup(
            titleKey: 'settings.notification.activity.events.title',
            descriptionKey: 'settings.notification.activity.events.description',
            child: _ToggleGrid(
              children: [
                _CompactToggle(
                  settingKey: const Key('notification-activity-online'),
                  icon: StarBridgeIconSemantic.connected,
                  titleKey: 'settings.notification.activity.event.online',
                  value: activity.notifyOnline,
                  enabled: enabled && activity.enabled,
                  color: tokens.colors.info,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(notifyOnline: value),
                    ),
                  ),
                ),
                _CompactToggle(
                  settingKey: const Key('notification-activity-offline'),
                  icon: StarBridgeIconSemantic.disconnected,
                  titleKey: 'settings.notification.activity.event.offline',
                  value: activity.notifyOffline,
                  enabled: enabled && activity.enabled,
                  color: tokens.colors.offline,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(notifyOffline: value),
                    ),
                  ),
                ),
                _CompactToggle(
                  settingKey: const Key('notification-activity-game-start'),
                  icon: StarBridgeIconSemantic.statusGame,
                  titleKey: 'settings.notification.activity.event.gameStart',
                  value: activity.notifyGameStarted,
                  enabled: enabled && activity.enabled,
                  color: tokens.colors.success,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(
                        notifyGameStarted: value,
                      ),
                    ),
                  ),
                ),
                _CompactToggle(
                  settingKey: const Key('notification-activity-game-stop'),
                  icon: StarBridgeIconSemantic.statusGame,
                  titleKey: 'settings.notification.activity.event.gameStop',
                  value: activity.notifyGameStopped,
                  enabled: enabled && activity.enabled,
                  color: tokens.colors.warning,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(
                        notifyGameStopped: value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.space.sm),
          _ActivityGroup(
            titleKey: 'settings.notification.activity.behavior.title',
            descriptionKey:
                'settings.notification.activity.behavior.description',
            child: Column(
              children: [
                NotificationToggleRow(
                  settingKey: const Key(
                    'notification-activity-background-only',
                  ),
                  titleKey:
                      'settings.notification.activity.backgroundOnly.title',
                  descriptionKey: 'settings.notification.activity.backgroundOnly.description',
                  value: activity.backgroundOnly,
                  enabled: enabled && activity.enabled,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(backgroundOnly: value),
                    ),
                  ),
                ),
                NotificationToggleRow(
                  settingKey: const Key('notification-activity-reduce-in-game'),
                  titleKey: 'settings.notification.activity.reduceInGame.title',
                  descriptionKey:
                      'settings.notification.activity.reduceInGame.description',
                  value: activity.reduceInGame,
                  enabled: enabled && activity.enabled,
                  onChanged: (value) => onSave(
                    settings.copyWith(
                      playerActivity: activity.copyWith(reduceInGame: value),
                    ),
                  ),
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityGroup extends StatelessWidget {
  const _ActivityGroup({
    required this.titleKey,
    required this.descriptionKey,
    required this.child,
  });

  final String titleKey;
  final String descriptionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: tokens.surfaces.ground.fill,
        border: Border.all(
          color: tokens.surfaces.panel.border,
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          SizedBox(height: tokens.space.sm),
          child,
        ],
      ),
    );
  }
}

class _ToggleGrid extends StatelessWidget {
  const _ToggleGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860
            ? 4
            : constraints.maxWidth >= 470
            ? 2
            : 1;
        final gap = tokens.space.xs;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _CompactToggle extends StatelessWidget {
  const _CompactToggle({
    required this.settingKey,
    required this.icon,
    required this.titleKey,
    this.titleOverride,
    required this.value,
    required this.enabled,
    required this.color,
    required this.onChanged,
  });

  final String? titleOverride;
  final Key settingKey;
  final StarBridgeIconSemantic icon;
  final String titleKey;
  final bool value;
  final bool enabled;
  final Color color;
  final Future<bool> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final title = titleOverride ?? strings.text(titleKey);
    return Semantics(
      container: true,
      enabled: enabled,
      toggled: value,
      label: title,
      child: ExcludeSemantics(
        child: Material(
          color: value
              ? color.withValues(alpha: 0.09)
              : tokens.surfaces.panel.fill,
          borderRadius: tokens.shape.small,
          child: InkWell(
            onTap: enabled ? () => onChanged(!value) : null,
            borderRadius: tokens.shape.small,
            child: Container(
              padding: EdgeInsets.all(tokens.space.sm),
              decoration: BoxDecoration(
                border: Border.all(
                  color: value
                      ? color.withValues(alpha: 0.55)
                      : tokens.surfaces.panel.border,
                  width: tokens.stroke.hairline,
                ),
                borderRadius: tokens.shape.small,
              ),
              child: Row(
                children: [
                  StarBridgeIcon(
                    icon,
                    size: tokens.icons.medium,
                    color: enabled ? color : tokens.colors.textDisabled,
                  ),
                  SizedBox(width: tokens.space.xs),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
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
      ),
    );
  }
}
