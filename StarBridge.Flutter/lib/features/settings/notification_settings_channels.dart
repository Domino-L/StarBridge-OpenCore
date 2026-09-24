import 'package:flutter/material.dart';

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
    super.key,
  });

  final NotificationSettingsValue settings;
  final bool showSound;
  final DesktopNotificationPort? desktop;
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
          if (!settings.localInAppOnly ||
              settings.directMessageDeliveryAvailable) ...[
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
                  child: NotificationToggleRow(
                    settingKey: const Key(
                      'notification-channel-direct-message',
                    ),
                    titleKey:
                        'settings.notification.channels.directMessage.title',
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
            onTest: () => showStarBridgeNotificationToast(
              context,
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
  final VoidCallback onTest;
  final bool localOnly;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: tokens.space.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final selector = DropdownButtonFormField<DesktopNotificationPosition>(
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
                OutlinedButton.icon(
                  key: const Key('notification-test-button'),
                  onPressed: enabled ? onTest : null,
                  icon: const StarBridgeIcon(
                    StarBridgeIconSemantic.notifications,
                    size: 16,
                  ),
                  label: Text(
                    strings.text('settings.notification.test.action'),
                  ),
                ),
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
              OutlinedButton.icon(
                key: const Key('notification-test-button'),
                onPressed: enabled ? onTest : null,
                icon: const StarBridgeIcon(
                  StarBridgeIconSemantic.notifications,
                  size: 16,
                ),
                label: Text(strings.text('settings.notification.test.action')),
              ),
            ],
          );
        },
      ),
    );
  }
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
    return Semantics(
      selected: selected,
      enabled: enabled,
      button: true,
      label: strings.text(_previewTitleKey(mode)),
      hint: strings.text(
        localOnly
            ? 'settings.notification.local.preview.${mode.name}'
            : _previewBodyKey(mode),
      ),
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? tokens.surfaces.selected.fill
              : tokens.surfaces.ground.fill,
          borderRadius: tokens.shape.small,
          child: InkWell(
            key: Key('notification-preview-${mode.name}'),
            onTap: enabled && !selected ? onSelect : null,
            borderRadius: tokens.shape.small,
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
