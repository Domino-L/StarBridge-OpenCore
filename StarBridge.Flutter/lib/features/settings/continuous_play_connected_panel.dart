import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'continuous_play_controller.dart';
import 'notification_settings_models.dart';
import 'notification_settings_play_reminders.dart';
import 'notification_editor_frame.dart';

/// Dialog content for the device-local reminder. The caller owns the controller.
class ContinuousPlayConnectedPanel extends StatefulWidget {
  const ContinuousPlayConnectedPanel({required this.controller, super.key});

  final ContinuousPlayController controller;

  @override
  State<ContinuousPlayConnectedPanel> createState() =>
      _ContinuousPlayConnectedPanelState();
}

class _ContinuousPlayConnectedPanelState
    extends State<ContinuousPlayConnectedPanel> {
  int _formGeneration = 0;
  bool _wasBusy = false;
  bool _lastWasSave = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _wasBusy = widget.controller.value.busy;
    widget.controller.addListener(_changed);
    if (widget.controller.value.settings == null && !_wasBusy) {
      widget.controller.refresh();
    }
  }

  void _changed() {
    final busy = widget.controller.value.busy;
    setState(() {
      // The reused dropdown owns FormField state. Reset even after failed writes,
      // when its initialValue is unchanged but the user picked a different value.
      if (_wasBusy && !busy) _formGeneration++;
      _wasBusy = busy;
    });
  }

  @override
  void didUpdateWidget(ContinuousPlayConnectedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _formGeneration++;
      _lastWasSave = false;
      _attach();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<bool> _save(NotificationSettingsValue value) {
    _lastWasSave = true;
    final reminder = value.continuousPlay;
    final drafts = NotificationDraftScope.of(context);
    final current = widget.controller.value.settings;
    if (drafts != null && current != null) {
      drafts.edit(
        'notification-play',
        (current.enabled, current.firstMinutes, current.repeatMinutes),
        (
          reminder.enabled,
          reminder.firstReminderMinutes,
          reminder.repeatReminderMinutes,
        ),
        (next) async {
          if (widget.controller.value.settings?.revision != current.revision) {
            return false;
          }
          return widget.controller.save(
            enabled: next.$1,
            firstMinutes: next.$2,
            repeatMinutes: next.$3,
          );
        },
      );
      return Future.value(true);
    }
    return widget.controller.save(
      enabled: reminder.enabled,
      firstMinutes: reminder.firstReminderMinutes,
      repeatMinutes: reminder.repeatReminderMinutes,
    );
  }

  void _reload() {
    _lastWasSave = false;
    widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.controller.value;
    final current = view.settings;
    final drafts = NotificationDraftScope.of(context);
    final desired = current == null
        ? null
        : drafts?.value('notification-play', (
            current.enabled,
            current.firstMinutes,
            current.repeatMinutes,
          ));
    final copy = _Copy(Localizations.localeOf(context));
    final tokens = context.tokens;
    return SizedBox(
      width: 760,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (current == null && !view.failed)
              Padding(
                key: const Key('continuous-play-loading'),
                padding: EdgeInsets.all(tokens.space.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(semanticsLabel: copy.loading),
                    SizedBox(height: tokens.space.sm),
                    Text(copy.loading),
                  ],
                ),
              ),
            if (view.failed) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  current != null && _lastWasSave
                      ? copy.saveFailed
                      : copy.readFailed,
                  key: const Key('continuous-play-failure'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.warning),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  key: const Key('continuous-play-reload'),
                  onPressed: view.busy ? null : _reload,
                  child: Text(copy.reload),
                ),
              ),
              SizedBox(height: tokens.space.sm),
            ],
            if (current != null) ...[
              if (view.busy) ...[
                LinearProgressIndicator(
                  key: const Key('continuous-play-busy'),
                  semanticsLabel: _lastWasSave ? copy.saving : copy.loading,
                ),
                SizedBox(height: tokens.space.sm),
              ],
              ContinuousPlayReminderPanel(
                key: ValueKey((_formGeneration, drafts?.epoch)),
                settings: _panelValue(
                  desired == null
                      ? current
                      : ContinuousPlayValue(
                          enabled: desired.$1,
                          firstMinutes: desired.$2,
                          repeatMinutes: desired.$3,
                          revision: current.revision,
                        ),
                ),
                enabled: !view.busy && !(drafts?.saving ?? false),
                onSave: _save,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Presentation-only envelope required by the existing panel. It reads only
// continuousPlay; no channel/audience values below are displayed or persisted.
// The independent port writes exactly the three real reminder settings.
NotificationSettingsValue _panelValue(ContinuousPlayValue current) =>
    NotificationSettingsValue(
      localInAppOnly: true,
      channels: const NotificationChannelSettings(
        inAppEnabled: false,
        windowsDesktopEnabled: false,
        directMessageWindowsEnabled: false,
        overlayEnabled: false,
        desktopPosition: DesktopNotificationPosition.bottomRight,
        sound: NotificationSoundSettings.notImplemented(),
      ),
      sourceRules: const [],
      previewMode: NotificationPreviewMode.hiddenDetails,
      playerActivity: PlayerActivityNotificationSettings.migratedDefault(),
      continuousPlay: ContinuousPlayReminderSettings(
        enabled: current.enabled,
        firstReminderMinutes: current.firstMinutes,
        repeatReminderMinutes: current.repeatMinutes,
      ),
    );

class _Copy {
  _Copy(Locale locale)
    : english = locale.languageCode == 'en',
      traditional = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
  final bool english;
  final bool traditional;
  String get loading => english
      ? 'Loading settings…'
      : traditional
      ? '正在讀取設定…'
      : '正在读取设置…';
  String get saving => english
      ? 'Saving…'
      : traditional
      ? '正在儲存…'
      : '正在保存…';
  String get readFailed => english
      ? 'Unable to load reminder settings.'
      : traditional
      ? '暫時無法讀取提醒設定。'
      : '暂时无法读取提醒设置。';
  String get saveFailed => english
      ? 'Could not confirm the save. Reload to check your settings.'
      : traditional
      ? '未能確認儲存結果，請重新讀取設定。'
      : '未能确认保存结果，请重新读取设置。';
  String get reload => english
      ? 'Reload settings'
      : traditional
      ? '重新讀取'
      : '重新读取';
}
