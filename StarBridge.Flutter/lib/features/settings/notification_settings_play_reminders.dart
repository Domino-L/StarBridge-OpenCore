import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'notification_settings_common.dart';
import 'notification_settings_models.dart';

class ContinuousPlayReminderPanel extends StatelessWidget {
  const ContinuousPlayReminderPanel({
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
    final reminder = settings.continuousPlay;
    final tokens = context.tokens;
    return NotificationSettingsPanel(
      key: const Key('notification-continuous-play-panel'),
      icon: StarBridgeIconSemantic.playtime,
      titleKey: 'settings.notification.play.title',
      descriptionKey: 'settings.notification.play.description',
      accentColor: tokens.colors.warning,
      child: Column(
        children: [
          NotificationToggleRow(
            settingKey: const Key('notification-play-enabled'),
            titleKey: 'settings.notification.play.enabled.title',
            descriptionKey: 'settings.notification.play.enabled.description',
            value: reminder.enabled,
            enabled: enabled,
            onChanged: (value) => onSave(
              settings.copyWith(
                continuousPlay: reminder.copyWith(enabled: value),
              ),
            ),
            showDivider: false,
            badgeKey: 'settings.notification.scope.device',
          ),
          SizedBox(height: tokens.space.sm),
          _ReminderIntervals(
            value: reminder,
            enabled: enabled && reminder.enabled,
            onFirstChanged: (minutes) => onSave(
              settings.copyWith(
                continuousPlay: reminder.copyWith(
                  firstReminderMinutes: minutes,
                ),
              ),
            ),
            onRepeatChanged: (minutes) => onSave(
              settings.copyWith(
                continuousPlay: reminder.copyWith(
                  repeatReminderMinutes: minutes,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderIntervals extends StatelessWidget {
  const _ReminderIntervals({
    required this.value,
    required this.enabled,
    required this.onFirstChanged,
    required this.onRepeatChanged,
  });

  final ContinuousPlayReminderSettings value;
  final bool enabled;
  final Future<bool> Function(int minutes) onFirstChanged;
  final Future<bool> Function(int minutes) onRepeatChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final selectors = <Widget>[
      _IntervalSelector(
        key: const Key('notification-play-first'),
        titleKey: 'settings.notification.play.first.title',
        descriptionKey: 'settings.notification.play.first.description',
        value: value.firstReminderMinutes,
        options: ContinuousPlayReminderSettings.supportedFirstReminderMinutes,
        enabled: enabled,
        onChanged: onFirstChanged,
      ),
      _IntervalSelector(
        key: const Key('notification-play-repeat'),
        titleKey: 'settings.notification.play.repeat.title',
        descriptionKey: 'settings.notification.play.repeat.description',
        value: value.repeatReminderMinutes,
        options: ContinuousPlayReminderSettings.supportedRepeatReminderMinutes,
        enabled: enabled,
        onChanged: onRepeatChanged,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
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
                strings.text('settings.notification.play.intervals.title'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              SizedBox(height: tokens.space.xs),
              if (stacked)
                Column(
                  children: [
                    selectors.first,
                    SizedBox(height: tokens.space.sm),
                    selectors.last,
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: selectors.first),
                    SizedBox(width: tokens.space.md),
                    Expanded(child: selectors.last),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _IntervalSelector extends StatelessWidget {
  const _IntervalSelector({
    required this.titleKey,
    required this.descriptionKey,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String titleKey;
  final String descriptionKey;
  final int value;
  final List<int> options;
  final bool enabled;
  final Future<bool> Function(int minutes) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.text(titleKey),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        SizedBox(height: tokens.space.xxs),
        Text(
          strings.text(descriptionKey),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: tokens.space.xs),
        DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          items: [
            for (final minutes in options)
              DropdownMenuItem(
                value: minutes,
                child: Text(_formatMinutes(strings, minutes)),
              ),
          ],
          onChanged: enabled
              ? (next) {
                  if (next != null && next != value) {
                    onChanged(next);
                  }
                }
              : null,
        ),
      ],
    );
  }
}

String _formatMinutes(AppStrings strings, int minutes) {
  if (minutes % 60 == 0) {
    return strings
        .text('settings.notification.play.hours')
        .replaceAll('{count}', (minutes ~/ 60).toString());
  }
  return strings
      .text('settings.notification.play.minutes')
      .replaceAll('{count}', minutes.toString());
}
