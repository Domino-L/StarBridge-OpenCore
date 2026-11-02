import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_slider.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'privacy_page_drafts.dart';
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
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin<NotificationAudioPanel> {
  double? _volume;
  int _binding = 0, _completed = 0, _phase = 0;
  bool _wasBusy = false;
  PrivacyPageDrafts? _drafts;
  int? _draftEpoch;
  InteractionSource _source = InteractionSource.programmatic;
  InteractionSource? _waitSource;
  NotificationAudioController get audio => widget.controller;
  // The fallback is a lazy list. Scrolling its item out of cache must not
  // invalidate a draft's in-flight commit; actual removal still disposes it.
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
    if (audio.value == null) unawaited(audio.refresh());
  }

  void _attach() {
    _wasBusy = audio.busy;
    _waitSource = null;
    audio.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (!_wasBusy && audio.busy) {
        _phase++;
        _source = captureStarBridgeActivationSource()();
        _waitSource = null;
      }
      if (_wasBusy && !audio.busy) _completed++;
      _wasBusy = audio.busy;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = NotificationDraftScope.of(context);
    if (!identical(next, _drafts) || next?.epoch != _draftEpoch) {
      _binding++;
      _volume = null;
      _drafts = next;
      _draftEpoch = next?.epoch;
    }
  }

  @override
  void didUpdateWidget(NotificationAudioPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      _binding++;
      _volume = null;
      _completed = 0;
      _source = InteractionSource.programmatic;
      unawaited(old.controller.stop());
      _attach();
      if (audio.value == null) unawaited(audio.refresh());
    }
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
    audio.removeListener(_changed);
    _binding++;
    unawaited(audio.stop());
    super.dispose();
  }

  String t(String key) => AppStrings.of(context).text('audio.$key');
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final owner = audio, binding = _binding;
        final value = owner.value;
        final drafts = NotificationDraftScope.of(context);
        final epoch = drafts?.epoch;
        bool current() =>
            mounted &&
            binding == _binding &&
            identical(owner, audio) &&
            identical(drafts, _drafts) &&
            epoch == drafts?.epoch;
        void command(InteractionSource source, Future<void> Function() action) {
          if (!current()) return;
          setState(() => _source = source);
          unawaited(runStarBridgeActivation<void>(source, action));
        }

        final desired = value == null
            ? null
            : drafts?.value('notification-audio', (
                    value.enabled,
                    value.volume,
                  )) ??
                  (value.enabled, value.volume);
        final blocked = owner.busy || (drafts?.saving ?? false);
        Future<void> change({bool? enabled, double? volume}) async {
          if (!current() ||
              owner.busy ||
              (drafts?.saving ?? false) ||
              value == null ||
              desired == null) {
            return;
          }
          setState(() => _source = currentStarBridgeActivationSource);
          if (drafts == null) {
            await owner.save(enabled: enabled, volume: volume);
            return;
          }
          drafts.edit(
            'notification-audio',
            (value.enabled, value.volume),
            (enabled ?? desired.$1, volume ?? desired.$2),
            (next) async {
              if (!current() ||
                  owner.busy ||
                  owner.value?.revision != value.revision) {
                return false;
              }
              await owner.save(enabled: next.$1, volume: next.$2);
              return current() &&
                  owner.error == null &&
                  owner.value?.enabled == next.$1 &&
                  owner.value?.volume == next.$2;
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
            child: StarBridgeInteractionRegion(
              child: Builder(
                builder: (context) {
                  final data = InteractionScope.of(context);
                  // Resolve this task's opening fact once. Keep live settings,
                  // but never relabel a held request after an unrelated rebuild.
                  final waitSource = _waitSource ??=
                      resolveStarBridgeInitialReadSource(context, _source);
                  final effective = data.copyWith(
                    reduceMotion:
                        data.reduceMotion ||
                        waitSource == InteractionSource.keyboard,
                  );
                  return Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (value != null) ...[
                            StarBridgeSwitch.tile(
                              preserveNativeTile: true,
                              controlKey: const Key('audio-enabled'),
                              label: t('enabled'),
                              titleWidget: Text(
                                t('enabled'),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              subtitle: t(
                                desired!.$1 && desired.$2 > 0
                                    ? 'ready'
                                    : 'muted',
                              ),
                              subtitleWidget: Text(
                                t(
                                  desired.$1 && desired.$2 > 0
                                      ? 'ready'
                                      : 'muted',
                                ),
                              ),
                              value: desired.$1,
                              onChanged: blocked
                                  ? null
                                  : (v) => change(enabled: v),
                            ),
                            Row(
                              children: [
                                Text(t('volume')),
                                const Spacer(),
                                Text(
                                  '${((_volume ?? desired.$2) * 100).round()}%',
                                ),
                              ],
                            ),
                            StarBridgeSlider(
                              key: ValueKey((binding, epoch)),
                              controlKey: const Key('audio-volume'),
                              semanticLabel: t('volume'),
                              value: _volume ?? desired.$2,
                              divisions: 100,
                              valueLabel: (value) =>
                                  '${(value * 100).round()}%',
                              onChanged: blocked
                                  ? null
                                  : (v) {
                                      if (current() &&
                                          !owner.busy &&
                                          !(drafts?.saving ?? false)) {
                                        setState(() => _volume = v);
                                      }
                                    },
                              onChangeCancel: () {
                                if (current()) setState(() => _volume = null);
                              },
                              onChangeEnd: (v) async {
                                await change(volume: v);
                                if (current()) setState(() => _volume = null);
                              },
                            ),
                            Text(
                              t('local'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t('automatic'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            if (drafts != null)
                              Text(
                                Localizations.localeOf(context).languageCode ==
                                        'en'
                                    ? 'Preview uses your saved sound settings.'
                                    : Localizations.localeOf(context)
                                                  .countryCode ==
                                              'TW' ||
                                          Localizations.localeOf(context)
                                                  .scriptCode ==
                                              'Hant'
                                    ? '試聽使用已儲存的聲音設定。'
                                    : '试听使用已保存的声音设置。',
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                StarBridgeActionButton(
                                  controlKey: const Key('audio-preview'),
                                  kind: StarBridgeActionKind.primary,
                                  onActivate: !blocked && owner.canPreview
                                      ? (source) =>
                                            command(source, owner.preview)
                                      : null,
                                  child: Text(t('preview')),
                                ),
                                StarBridgeActionButton(
                                  controlKey: const Key('audio-stop'),
                                  onActivate: owner.status == 'played'
                                      ? (source) => command(source, owner.stop)
                                      : null,
                                  child: Text(t('stop')),
                                ),
                              ],
                            ),
                            if (!value.previewAvailable)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  t('assets'),
                                  style: TextStyle(
                                    color: context.tokens.colors.warning,
                                  ),
                                ),
                              ),
                          ],
                          if (owner.busy)
                            InteractionScope(
                              data: effective,
                              child: Semantics(
                                liveRegion: true,
                                child: SuiteBusyLabel(t('pending')),
                              ),
                            ),
                          if (audio.error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              t(audio.error!),
                              style: TextStyle(
                                color: context.tokens.colors.warning,
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: StarBridgeActionButton(
                                controlKey: const Key('audio-retry'),
                                kind: StarBridgeActionKind.quiet,
                                onActivate: owner.busy
                                    ? null
                                    : (source) =>
                                          command(source, owner.refresh),
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
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: InteractionScope(
                              data: effective,
                              child: SuiteBusyFrame(
                                key: ValueKey((binding, _phase)),
                                busy: owner.busy,
                                doneToken: _completed,
                                doneOutcome: owner.error == null
                                    ? TaskOutcome.success
                                    : TaskOutcome.failure,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
