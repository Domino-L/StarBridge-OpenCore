import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'notification_settings_common.dart';
import 'notification_audio_controller.dart';
import 'notification_editor_frame.dart';

class NotificationAudioPanel extends StatefulWidget {
  const NotificationAudioPanel({required this.controller, super.key});
  final NotificationAudioController controller;
  @override
  State<NotificationAudioPanel> createState() => _NotificationAudioPanelState();
}

class _NotificationAudioPanelState extends State<NotificationAudioPanel>
    with WidgetsBindingObserver {
  double? _volume;
  NotificationAudioController get audio => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (audio.value == null) unawaited(audio.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(audio.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(audio.stop());
    super.dispose();
  }

  String t(String key) => AppStrings.of(context).text('audio.$key');
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: audio,
    builder: (context, _) {
      final value = audio.value;
      final drafts = NotificationDraftScope.of(context);
      final desired = value == null
          ? null
          : drafts?.value('notification-audio', (
                  value.enabled,
                  value.volume,
                )) ??
                (value.enabled, value.volume);
      final blocked = audio.busy || (drafts?.saving ?? false);
      Future<void> change({bool? enabled, double? volume}) async {
        if (value == null || desired == null) return;
        if (drafts == null) {
          await audio.save(enabled: enabled, volume: volume);
          return;
        }
        drafts.edit(
          'notification-audio',
          (value.enabled, value.volume),
          (enabled ?? desired.$1, volume ?? desired.$2),
          (next) async {
            if (audio.busy || audio.value?.revision != value.revision) {
              return false;
            }
            await audio.save(enabled: next.$1, volume: next.$2);
            return audio.error == null &&
                audio.value?.enabled == next.$1 &&
                audio.value?.volume == next.$2;
          },
        );
      }

      return NotificationSettingsPanel(
        key: const Key('notification-audio-panel'),
        icon: StarBridgeIconSemantic.reminder,
        titleKey: 'audio.title',
        descriptionKey: 'audio.description',
        accentColor: context.tokens.colors.info,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value != null) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  key: const Key('audio-enabled'),
                  title: Text(
                    t('enabled'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    t(desired!.$1 && desired.$2 > 0 ? 'ready' : 'muted'),
                  ),
                  value: desired.$1,
                  onChanged: blocked ? null : (v) => change(enabled: v),
                ),
                Row(
                  children: [
                    Text(t('volume')),
                    const Spacer(),
                    Text('${((_volume ?? desired.$2) * 100).round()}%'),
                  ],
                ),
                Slider(
                  key: const Key('audio-volume'),
                  value: _volume ?? desired.$2,
                  divisions: 100,
                  label: '${((_volume ?? desired.$2) * 100).round()}%',
                  onChanged: blocked
                      ? null
                      : (v) => setState(() => _volume = v),
                  onChangeEnd: (v) async {
                    await change(volume: v);
                    if (mounted) setState(() => _volume = null);
                  },
                ),
                Text(t('local'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(
                  t('automatic'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (drafts != null)
                  Text(
                    Localizations.localeOf(context).languageCode == 'en'
                        ? 'Preview uses your saved sound settings.'
                        : Localizations.localeOf(context).countryCode == 'TW' ||
                              Localizations.localeOf(context).scriptCode ==
                                  'Hant'
                        ? '試聽使用已儲存的聲音設定。'
                        : '试听使用已保存的声音设置。',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: !blocked && audio.canPreview
                          ? audio.preview
                          : null,
                      child: Text(t('preview')),
                    ),
                    OutlinedButton(
                      onPressed: audio.status == 'played' ? audio.stop : null,
                      child: Text(t('stop')),
                    ),
                  ],
                ),
                if (!value.previewAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      t('assets'),
                      style: TextStyle(color: context.tokens.colors.warning),
                    ),
                  ),
              ],
              if (audio.busy) const LinearProgressIndicator(),
              if (audio.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  t(audio.error!),
                  style: TextStyle(color: context.tokens.colors.warning),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: audio.busy ? null : audio.refresh,
                    child: Text(t('retry')),
                  ),
                ),
              ] else if (audio.status != null) ...[
                const SizedBox(height: 8),
                Text(
                  t(audio.status!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
