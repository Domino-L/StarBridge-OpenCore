import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../notifications/starbridge_notification_toast.dart';
import 'notification_settings_common.dart';
import 'notification_settings_models.dart';
import '../../platform/host/desktop_notification_port.dart';
import 'desktop_notification_test_button.dart';

class NotificationChannelPanel extends StatelessWidget {
  const NotificationChannelPanel({
    required this.settings,
    required this.enabled,
    required this.onSave,
    this.showSound = true,
    this.desktop,
    this.onPreviewRally,
    super.key,
  });

  final NotificationSettingsValue settings;
  final bool showSound;
  final DesktopNotificationPort? desktop;
  // Shows a sample rally alert; null when the Host cannot.
  final Future<void> Function()? onPreviewRally;
  final bool enabled;
  final Future<bool> Function(NotificationSettingsValue settings) onSave;

  @override
  Widget build(BuildContext context) {
    final channels = settings.channels;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final overlayColor = tokens.domainColors
        .resolve(DomainColorRole.recon)
        .foreground;
    final showDirectMessage =
        !settings.localInAppOnly || settings.directMessageDeliveryAvailable;
    final showTrade =
        !settings.localInAppOnly || settings.tradeDeliveryAvailable;
    return NotificationSettingsPanel(
      key: const Key('notification-channel-panel'),
      icon: StarBridgeIconSemantic.notifications,
      titleKey: 'settings.notification.channels.title',
      descriptionKey: 'settings.notification.channels.description',
      accentColor: tokens.colors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (settings.localInAppOnly)
            NotificationToggleRow(
              settingKey: const Key('notification-channel-in-app'),
              titleKey: 'settings.notification.local.enabled',
              descriptionKey: 'settings.notification.local.enabledDescription',
              value: channels.inAppEnabled,
              enabled: enabled,
              leading: StarBridgeIcon(
                StarBridgeIconSemantic.notifications,
                size: tokens.icons.medium,
                color: tokens.colors.info,
              ),
              onChanged: (value) => onSave(
                settings.copyWith(
                  channels: channels.copyWith(inAppEnabled: value),
                ),
              ),
            ),
          if (!settings.localInAppOnly) ...[
            NotificationReadOnlyRow(
              icon: StarBridgeIconSemantic.notifications,
              titleKey: 'settings.notification.channels.history.title',
              descriptionKey:
                  'settings.notification.channels.history.description',
              statusKey: 'settings.notification.channels.history.required',
              color: tokens.colors.success,
            ),
          ],
          if (!settings.localInAppOnly ||
              settings.desktopDeliveryAvailable) ...[
            NotificationToggleRow(
              settingKey: const Key('notification-channel-windows'),
              titleKey: 'settings.notification.channels.windows.title',
              descriptionKey: settings.localInAppOnly
                  ? 'settings.notification.local.windowsDescription'
                  : 'settings.notification.channels.windows.description',
              value: channels.windowsDesktopEnabled,
              // Off by default; recommended until the user turns it on.
              recommendKey: channels.windowsDesktopEnabled
                  ? null
                  : 'settings.notification.channels.windows.recommended',
              showDivider: false,
              enabled: enabled,
              onChanged: (value) => onSave(
                settings.copyWith(
                  channels: channels.copyWith(windowsDesktopEnabled: value),
                ),
              ),
              leading: StarBridgeIcon(
                StarBridgeIconSemantic.windowRestore,
                size: tokens.icons.medium,
                color: tokens.colors.info,
              ),
              badgeKey: settings.localInAppOnly
                  ? null
                  : 'settings.notification.scope.device',
            ),
            if (settings.localInAppOnly && desktop != null)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: tokens.icons.medium + tokens.space.sm,
                  bottom: tokens.space.sm,
                ),
                child: DesktopNotificationTestButton(
                  port: desktop!,
                  enabled: enabled && channels.windowsDesktopEnabled,
                ),
              ),
          ],
          if (showDirectMessage || showTrade) ...[
            Padding(
              key: const Key('notification-desktop-child'),
              padding: EdgeInsetsDirectional.only(
                start: tokens.icons.medium + tokens.space.sm,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surfaces.ground.fill,
                  borderRadius: tokens.shape.small,
                ),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: tokens.space.sm),
                  child: Column(
                    children: [
                      if (showDirectMessage)
                        NotificationToggleRow(
                          settingKey: const Key(
                            'notification-channel-direct-message',
                          ),
                          titleKey: 'settings.notification.channels.directMessage.title',
                          descriptionKey: 'settings.notification.channels.directMessage.description',
                          value: channels.directMessageWindowsEnabled,
                          showDivider: false,
                          enabled: enabled && channels.windowsDesktopEnabled,
                          onChanged: (value) => onSave(
                            settings.copyWith(
                              channels: channels.copyWith(
                                directMessageWindowsEnabled: value,
                              ),
                            ),
                          ),
                          leading: StarBridgeIcon(
                            StarBridgeIconSemantic.friends,
                            size: tokens.icons.medium,
                            color: tokens.colors.warning,
                          ),
                          badgeKey: 'settings.notification.channels.directMessage.defaultOff',
                        ),
                      if (showTrade)
                        NotificationToggleRow(
                          settingKey: const Key('notification-channel-trade'),
                          titleKey:
                              'settings.notification.channels.trade.title',
                          descriptionKey: 'settings.notification.channels.trade.description',
                          value: channels.tradeWindowsEnabled,
                          showDivider: false,
                          enabled: enabled && channels.windowsDesktopEnabled,
                          onChanged: (value) => onSave(
                            settings.copyWith(
                              channels: channels.copyWith(
                                tradeWindowsEnabled: value,
                              ),
                            ),
                          ),
                          leading: StarBridgeIcon(
                            StarBridgeIconSemantic.marketplace,
                            size: tokens.icons.medium,
                            color: tokens.colors.success,
                          ),
                          badgeKey:
                              'settings.notification.channels.trade.defaultOn',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (!settings.localInAppOnly ||
              settings.overlayDeliveryAvailable) ...[
            NotificationToggleRow(
              settingKey: const Key('notification-channel-overlay'),
              titleKey: 'settings.notification.channels.overlay.title',
              descriptionKey: settings.localInAppOnly
                  ? 'settings.notification.local.overlayDescription'
                  : 'settings.notification.channels.overlay.description',
              value: channels.overlayEnabled,
              enabled: enabled,
              onChanged: (value) => onSave(
                settings.copyWith(
                  channels: channels.copyWith(overlayEnabled: value),
                ),
              ),
              leading: StarBridgeIcon(
                StarBridgeIconSemantic.overlay,
                size: tokens.icons.medium,
                color: overlayColor,
              ),
              badgeKey: settings.localInAppOnly
                  ? null
                  : 'settings.notification.scope.device',
            ),
          ],
          if (settings.rallyAlertsAvailable) ...[
            NotificationToggleRow(
              settingKey: const Key('notification-channel-rally'),
              titleKey: 'settings.notification.channels.rally.title',
              descriptionKey:
                  'settings.notification.channels.rally.description',
              value: channels.rallyAlertsEnabled,
              // The preview button below belongs to this row.
              showDivider: onPreviewRally == null,
              enabled: enabled,
              onChanged: (value) => onSave(
                settings.copyWith(
                  channels: channels.copyWith(rallyAlertsEnabled: value),
                ),
              ),
              leading: StarBridgeIcon(
                StarBridgeIconSemantic.officialFleet,
                size: tokens.icons.medium,
                color: tokens.colors.warning,
              ),
              badgeKey: 'settings.notification.scope.device',
            ),
            if (onPreviewRally != null)
              Container(
                alignment: AlignmentDirectional.centerStart,
                padding: EdgeInsetsDirectional.only(
                  start: tokens.icons.medium + tokens.space.sm,
                  bottom: tokens.space.sm,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tokens.surfaces.panel.border,
                      width: tokens.stroke.hairline,
                    ),
                  ),
                ),
                child: StarBridgeTooltip(
                  message: strings.text(
                    'settings.notification.channels.rally.previewHint',
                  ),
                  child: StarBridgeActionButton(
                    controlKey: const Key('notification-rally-preview'),
                    semanticLabel: strings.text(
                      'settings.notification.channels.rally.preview',
                    ),
                    onActivate: enabled && channels.rallyAlertsEnabled
                        ? (_) => unawaited(onPreviewRally!())
                        : null,
                    child: Text(
                      strings.text(
                        'settings.notification.channels.rally.preview',
                      ),
                    ),
                  ),
                ),
              ),
          ],
          if (showSound) ...[
            if (channels.sound.availability !=
                NotificationSoundAvailability.available)
              NotificationReadOnlyRow(
                icon: StarBridgeIconSemantic.reminder,
                titleKey: 'settings.notification.channels.sound.title',
                descriptionKey:
                    'settings.notification.channels.sound.pendingDescription',
                statusKey: 'settings.notification.channels.sound.pending',
                color: tokens.colors.textSecondary,
                showDivider: false,
              )
            else
              NotificationToggleRow(
                settingKey: const Key('notification-channel-sound'),
                titleKey: 'settings.notification.channels.sound.title',
                descriptionKey:
                    'settings.notification.channels.sound.description',
                value: channels.sound.enabled,
                enabled: enabled,
                onChanged: (value) => onSave(
                  settings.copyWith(
                    channels: channels.copyWith(
                      sound: channels.sound.copyWith(enabled: value),
                    ),
                  ),
                ),
                showDivider: false,
              ),
          ],
          SizedBox(height: tokens.space.md),
          _DesktopPositionSelector(
            localOnly: settings.localInAppOnly,
            value: channels.desktopPosition,
            enabled: enabled,
            onChanged: (value) => onSave(
              settings.copyWith(
                channels: channels.copyWith(desktopPosition: value),
              ),
            ),
            onTest: (source) => showStarBridgeNotificationToast(
              context,
              source: source,
              alignment: _toastAlignment(channels.desktopPosition),
              title: strings.text(
                settings.localInAppOnly
                    ? 'settings.notification.local.testTitle'
                    : 'settings.notification.test.title',
              ),
              message: strings.text(switch (settings.previewMode) {
                NotificationPreviewMode.fullContent =>
                  'settings.notification.test.body',
                NotificationPreviewMode.sourceOnly =>
                  'settings.notification.local.sourceBody',
                NotificationPreviewMode.hiddenDetails =>
                  'settings.notification.local.hiddenBody',
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationPreviewPanel extends StatelessWidget {
  const NotificationPreviewPanel({
    required this.settings,
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final NotificationSettingsValue settings;
  final bool enabled;
  final Future<bool> Function(NotificationSettingsValue settings) onSave;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return NotificationSettingsPanel(
      key: const Key('notification-preview-panel'),
      icon: StarBridgeIconSemantic.privacy,
      titleKey: settings.localInAppOnly
          ? 'settings.notification.local.previewTitle'
          : 'settings.notification.preview.title',
      descriptionKey: 'settings.notification.preview.description',
      accentColor: tokens.domainColors
          .resolve(DomainColorRole.recon)
          .foreground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 780 ? 3 : 1;
              final gap = tokens.space.sm;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final mode in NotificationPreviewMode.values)
                    SizedBox(
                      width: width,
                      child: _PreviewChoice(
                        localOnly: settings.localInAppOnly,
                        mode: mode,
                        selected: settings.previewMode == mode,
                        enabled: enabled,
                        onSelect: () =>
                            onSave(settings.copyWith(previewMode: mode)),
                      ),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: tokens.space.md),
          Container(
            key: const Key('notification-preview-example'),
            padding: EdgeInsets.all(tokens.space.md),
            decoration: BoxDecoration(
              color: tokens.surfaces.ground.fill,
              borderRadius: tokens.shape.small,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.of(context)
                      .text('settings.notification.preview.example'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(height: tokens.space.sm),
                Text(
                  AppStrings.of(context)
                      .text(switch (settings.previewMode) {
                        NotificationPreviewMode.fullContent =>
                          settings.localInAppOnly
                              ? 'settings.notification.local.fullBody'
                              : 'settings.notification.test.body',
                        NotificationPreviewMode.sourceOnly =>
                          'settings.notification.local.sourceBody',
                        NotificationPreviewMode.hiddenDetails =>
                          'settings.notification.local.hiddenBody',
                      })
                      .replaceAll('{invitations}', '1')
                      .replaceAll('{applications}', '2'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (settings.localInAppOnly &&
                    settings.previewMode !=
                        NotificationPreviewMode.hiddenDetails) ...[
                  SizedBox(height: tokens.space.xs),
                  Text(
                    AppStrings.of(context).text(
                      settings.previewMode ==
                              NotificationPreviewMode.fullContent
                          ? 'settings.notification.local.directExample.full'
                          : 'settings.notification.local.directExample.source',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopPositionSelector extends StatelessWidget {
  const _DesktopPositionSelector({
    required this.localOnly,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onTest,
  });

  final DesktopNotificationPosition value;
  final bool enabled;
  final Future<bool> Function(DesktopNotificationPosition value) onChanged;
  final ValueChanged<InteractionSource> onTest;
  final bool localOnly;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: tokens.space.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final selector =
              StarBridgeSelectFormField<DesktopNotificationPosition>(
                identity: 'notification-desktop-position',
                controlKey: const Key('notification-desktop-position-control'),
                key: const Key('notification-desktop-position'),
                initialValue: value,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: strings.text(
                    localOnly
                        ? 'settings.notification.local.position'
                        : 'settings.notification.channels.position.label',
                  ),
                ),
                items: [
                  for (final position in DesktopNotificationPosition.values)
                    DropdownMenuItem(
                      value: position,
                      child: Text(strings.text(_positionKey(position))),
                    ),
                ],
                onChanged: enabled
                    ? (next) {
                        if (next != null) {
                          onChanged(next);
                        }
                      }
                    : null,
              );
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.text(
                    'settings.notification.channels.position.description',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: tokens.space.sm),
                selector,
                SizedBox(height: tokens.space.sm),
                _testButton(strings),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Text(
                  strings.text(
                    'settings.notification.channels.position.description',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              SizedBox(width: tokens.space.md),
              SizedBox(width: 220, child: selector),
              SizedBox(width: tokens.space.sm),
              _testButton(strings),
            ],
          );
        },
      ),
    );
  }

  Widget _testButton(AppStrings strings) => StarBridgeActionButton(
    controlKey: const Key('notification-test-button'),
    semanticLabel: strings.text('settings.notification.test.action'),
    onActivate: enabled ? onTest : null,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StarBridgeIcon(StarBridgeIconSemantic.notifications, size: 16),
        const SizedBox(width: 8),
        Text(strings.text('settings.notification.test.action')),
      ],
    ),
  );
}

Alignment _toastAlignment(DesktopNotificationPosition position) =>
    switch (position) {
      DesktopNotificationPosition.topLeft => Alignment.topLeft,
      DesktopNotificationPosition.bottomLeft => Alignment.bottomLeft,
      DesktopNotificationPosition.topRight => Alignment.topRight,
      DesktopNotificationPosition.bottomRight => Alignment.bottomRight,
    };

class _PreviewChoice extends StatelessWidget {
  const _PreviewChoice({
    required this.localOnly,
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final NotificationPreviewMode mode;
  final bool localOnly;
  final bool selected;
  final bool enabled;
  final Future<bool> Function() onSelect;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeInteractionRegion(
      child: Builder(
        builder: (_) => Semantics(
          inMutuallyExclusiveGroup: true,
          hint: strings.text(
            localOnly
                ? 'settings.notification.local.preview.${mode.name}'
                : _previewBodyKey(mode),
          ),
          child: Material(
            color: selected
                ? tokens.surfaces.selected.fill
                : tokens.surfaces.ground.fill,
            borderRadius: tokens.shape.small,
            child: SuitePressable(
              key: Key('notification-preview-${mode.name}'),
              kind: PressableKind.row,
              selected: selected,
              semanticSelected: selected,
              semanticLabel: strings.text(_previewTitleKey(mode)),
              excludeChildSemantics: true,
              baseRadius: tokens.shape.radiusSmall,
              onActivate: enabled
                  ? (source) {
                      if (!selected) {
                        unawaited(
                          runStarBridgeActivation<bool>(source, onSelect),
                        );
                      }
                    }
                  : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: EdgeInsets.all(tokens.space.sm),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? tokens.colors.accent
                        : tokens.surfaces.panel.border,
                    width: tokens.stroke.regular,
                  ),
                  borderRadius: tokens.shape.small,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.text(_previewTitleKey(mode)),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        if (selected)
                          StarBridgeIcon(
                            StarBridgeIconSemantic.connected,
                            size: tokens.icons.small,
                            color: tokens.colors.accent,
                          ),
                      ],
                    ),
                    SizedBox(height: tokens.space.xs),
                    Text(
                      strings.text(
                        localOnly
                            ? 'settings.notification.local.preview.${mode.name}'
                            : _previewBodyKey(mode),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _positionKey(DesktopNotificationPosition position) => switch (position) {
  DesktopNotificationPosition.topLeft =>
    'settings.notification.position.topLeft',
  DesktopNotificationPosition.bottomLeft =>
    'settings.notification.position.bottomLeft',
  DesktopNotificationPosition.topRight =>
    'settings.notification.position.topRight',
  DesktopNotificationPosition.bottomRight =>
    'settings.notification.position.bottomRight',
};

String _previewTitleKey(NotificationPreviewMode mode) => switch (mode) {
  NotificationPreviewMode.fullContent =>
    'settings.notification.preview.full.title',
  NotificationPreviewMode.sourceOnly =>
    'settings.notification.preview.source.title',
  NotificationPreviewMode.hiddenDetails =>
    'settings.notification.preview.hidden.title',
};

String _previewBodyKey(NotificationPreviewMode mode) => switch (mode) {
  NotificationPreviewMode.fullContent =>
    'settings.notification.preview.full.description',
  NotificationPreviewMode.sourceOnly =>
    'settings.notification.preview.source.description',
  NotificationPreviewMode.hiddenDetails =>
    'settings.notification.preview.hidden.description',
};
