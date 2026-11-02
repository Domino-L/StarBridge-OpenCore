import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' show act, loadFonts, scopedApp, size;
import 'interaction_batch3dw_test.dart' show NotificationMotionPort;

const _timeout = Timeout(Duration(seconds: 45));

/// A transport only: admission, receipts, preview epochs and drafts remain in
/// the real owners. These commands never reach playback or persistent storage.
class _AudioPort implements NotificationAudioPort {
  AudioPreferences value = const AudioPreferences(
    3,
    true,
    .65,
    true,
    doNotDisturb: true,
  );
  final reads = <InteractionSource>[];
  final saves = <(AudioPreferences, bool, double, bool?, InteractionSource)>[];
  final previews = <InteractionSource>[];
  final stops = <InteractionSource>[];
  Completer<AudioPreferences>? pendingRead, pendingSave;
  Completer<String>? pendingPreview;
  Object? saveFailure;
  final _readGates = <Completer<AudioPreferences>>[];
  final _saveGates = <Completer<AudioPreferences>>[];
  final _previewGates = <Completer<String>>[];

  Completer<AudioPreferences> holdRead() {
    final gate = Completer<AudioPreferences>();
    _readGates.add(gate);
    return pendingRead = gate;
  }

  Completer<AudioPreferences> holdSave() {
    final gate = Completer<AudioPreferences>();
    _saveGates.add(gate);
    return pendingSave = gate;
  }

  Completer<String> holdPreview() {
    final gate = Completer<String>();
    _previewGates.add(gate);
    return pendingPreview = gate;
  }

  @override
  Future<AudioPreferences> read() {
    reads.add(currentStarBridgeActivationSource);
    final gate = pendingRead;
    pendingRead = null;
    return gate?.future ?? Future.value(value);
  }

  @override
  Future<AudioPreferences> save(
    AudioPreferences current,
    bool enabled,
    double volume, {
    bool? doNotDisturb,
  }) async {
    saves.add((
      current,
      enabled,
      volume,
      doNotDisturb,
      currentStarBridgeActivationSource,
    ));
    final failure = saveFailure;
    if (failure != null) {
      throw failure;
    }
    final gate = pendingSave;
    pendingSave = null;
    if (gate != null) {
      return gate.future;
    }
    return value = AudioPreferences(
      current.revision + 1,
      enabled,
      volume,
      current.previewAvailable,
      doNotDisturb: doNotDisturb ?? current.doNotDisturb,
    );
  }

  void accept(Completer<AudioPreferences> gate) {
    final command = saves.last;
    value = AudioPreferences(
      command.$1.revision + 1,
      command.$2,
      command.$3,
      command.$1.previewAvailable,
      doNotDisturb: command.$4 ?? command.$1.doNotDisturb,
    );
    gate.complete(value);
  }

  @override
  Future<String> preview() {
    previews.add(currentStarBridgeActivationSource);
    final gate = pendingPreview;
    pendingPreview = null;
    return gate?.future ?? Future.value('played');
  }

  @override
  Future<void> stop() async {
    stops.add(currentStarBridgeActivationSource);
  }

  void releaseAll() {
    for (final gate in [..._readGates, ..._saveGates]) {
      if (!gate.isCompleted) {
        gate.complete(value);
      }
    }
    for (final gate in _previewGates) {
      if (!gate.isCompleted) {
        gate.complete('played');
      }
    }
  }
}

Future<void> _frames(WidgetTester t, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _panelApp(NotificationAudioController audio, InteractionSuite suite) =>
    scopedApp(
      SingleChildScrollView(child: NotificationAudioPanel(controller: audio)),
      suite,
    );

Widget _editorApp(
  NotificationAudioController audio,
  InteractionSuite suite,
  Object owner, {
  BridgeClientSession? session,
}) => scopedApp(
  SizedBox.expand(
    child: NotificationEditorFrame(
      owner: owner,
      session: session,
      child: ListView(children: [NotificationAudioPanel(controller: audio)]),
    ),
  ),
  suite,
);

Finder _switch() => find
    .ancestor(
      of: find.byKey(const Key('audio-enabled')),
      matching: find.byType(StarBridgeSwitch),
    )
    .first;

StarBridgeActionButton _button(WidgetTester t, String key) {
  final keyed = find.byKey(Key(key));
  if (t.widget(keyed) is StarBridgeActionButton) {
    return t.widget<StarBridgeActionButton>(keyed);
  }
  return t.widget<StarBridgeActionButton>(
    find
        .ancestor(of: keyed, matching: find.byType(StarBridgeActionButton))
        .first,
  );
}

Future<void> _toggle(WidgetTester t) async {
  await t.ensureVisible(_switch());
  await t.pump();
  await t.tap(_switch());
  await _frames(t, count: 2);
}

Future<void> _click(
  WidgetTester t,
  String key, {
  String source = 'pointer',
  String label = '',
}) async {
  await act(t, find.byKey(Key(key)), source, label);
  await _frames(t, count: 2);
}

PrivacyPageDrafts _drafts(WidgetTester t) =>
    NotificationDraftScope.of(t.element(find.byType(NotificationAudioPanel)))!;

SuiteBusyFrame _busyFrame(WidgetTester t) => t.widget<SuiteBusyFrame>(
  find.descendant(
    of: find.byType(NotificationAudioPanel),
    matching: find.byType(SuiteBusyFrame),
  ),
);

void _waitMotion(WidgetTester t, {required bool isStatic}) {
  final panel = find.byType(NotificationAudioPanel);
  final labels = find.descendant(
    of: panel,
    matching: find.byType(SuiteBusyLabel),
  );
  expect(labels, findsOneWidget);
  final frames = find.descendant(
    of: panel,
    matching: find.byType(SuiteBusyFrame),
  );
  for (final element in [...labels.evaluate(), ...frames.evaluate()]) {
    expect(InteractionScope.of(element).reduceMotion, isStatic);
  }
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await _frames(t, count: 2);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite audio held initial read uses one real owner and keeps duplicate admission',
      (t) async {
        size(t, const Size(1280, 1100));
        final port = _AudioPort();
        final gate = port.holdRead();
        final audio = NotificationAudioController(port);
        try {
          await t.pumpWidget(_panelApp(audio, suite));
          await _frames(t, count: 2);
          expect(port.reads, hasLength(1));
          expect(audio.value, isNull);
          expect(audio.busy, isTrue);
          expect(find.byKey(const Key('audio-enabled')), findsNothing);
          await audio.refresh();
          await audio.save(enabled: false);
          await audio.preview();
          expect(port.reads, hasLength(1));
          expect(port.saves, isEmpty);
          expect(port.previews, isEmpty);
          gate.complete(port.value);
          await _frames(t);
          expect(audio.value, same(port.value));
          expect(audio.value!.revision, 3);
          expect(audio.value!.doNotDisturb, isTrue);
          expect(audio.busy, isFalse);
          expect(_busyFrame(t).busy, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          port.releaseAll();
          await _frames(t, count: 2);
          await _unmount(t);
          audio.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio standalone save preserves receipt and captures each actual busy phase source',
      (t) async {
        size(t, const Size(1280, 1100));
        final port = _AudioPort();
        final audio = NotificationAudioController(port);
        try {
          await audio.refresh();
          final confirmed = audio.value!;
          await t.pumpWidget(_panelApp(audio, suite));
          await _frames(t);
          final staleToggle = t.widget<StarBridgeSwitch>(_switch()).onChanged!;
          final saving = port.holdSave();
          await _toggle(t);
          expect(port.saves, hasLength(1));
          expect(port.saves.single.$1, same(confirmed));
          expect(port.saves.single.$2, isFalse);
          expect(port.saves.single.$4, isTrue);
          expect(port.saves.single.$5, InteractionSource.pointer);
          expect(audio.value, same(confirmed));
          expect(audio.busy, isTrue);
          expect(t.widget<StarBridgeSwitch>(_switch()).onChanged, isNull);
          staleToggle(false);
          await audio.save(volume: .2);
          await audio.refresh();
          await audio.preview();
          expect(port.saves, hasLength(1));
          expect(port.reads, hasLength(1));
          expect(port.previews, isEmpty);
          _waitMotion(t, isStatic: false);
          port.accept(saving);
          await _frames(t);
          expect(audio.value!.enabled, isFalse);
          expect(audio.value!.revision, 4);
          expect(audio.status, 'saved');

          final reading = port.holdRead();
          final refresh = runStarBridgeActivation<void>(
            InteractionSource.keyboard,
            audio.refresh,
          );
          await _frames(t, count: 2);
          expect(port.reads.last, InteractionSource.keyboard);
          _waitMotion(t, isStatic: true);
          reading.complete(port.value);
          await refresh;
          await _frames(t);

          final nextSave = port.holdSave();
          final external = runStarBridgeActivation<void>(
            InteractionSource.programmatic,
            () => audio.save(volume: .2),
          );
          await _frames(t, count: 2);
          expect(port.saves, hasLength(2));
          expect(port.saves.last.$5, InteractionSource.programmatic);
          expect(audio.value!.revision, 4);
          _waitMotion(t, isStatic: false);
          port.accept(nextSave);
          await external;
          await _frames(t);
          expect(audio.value!.revision, 5);
          expect(audio.value!.volume, .2);
          expect(port.reads, hasLength(2));
          expect(port.previews, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          port.releaseAll();
          await _frames(t, count: 2);
          await _unmount(t);
          audio.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio failure keeps confirmed preferences and explicit retry only rereads',
      (t) async {
        size(t, const Size(1280, 1100));
        for (final failure in <Object>[
          const AudioFailure('conflict'),
          const AudioFailure('assets'),
          StateError('transport'),
        ]) {
          final port = _AudioPort()..saveFailure = failure;
          final audio = NotificationAudioController(port);
          try {
            await audio.refresh();
            final confirmed = audio.value;
            await t.pumpWidget(_panelApp(audio, suite));
            await _frames(t);
            await _toggle(t);
            await _frames(t);
            expect(audio.value, same(confirmed));
            expect(audio.value!.revision, 3);
            expect(
              audio.error,
              failure is AudioFailure ? failure.code : 'failed',
            );
            expect(audio.status, isNull);
            expect(audio.busy, isFalse);
            expect(_busyFrame(t).doneOutcome, TaskOutcome.failure);
            expect(port.saves, hasLength(1));
            expect(port.previews, isEmpty);
            final reading = port.holdRead();
            await _click(t, 'audio-retry', source: 'keyboard');
            expect(port.reads, hasLength(2));
            expect(port.reads.last, InteractionSource.keyboard);
            expect(port.saves, hasLength(1));
            expect(audio.value, same(confirmed));
            _waitMotion(t, isStatic: true);
            reading.complete(port.value);
            await _frames(t);
            expect(audio.error, isNull);
            expect(audio.value, same(confirmed));
            expect(port.saves, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            port.releaseAll();
            await _frames(t, count: 2);
            await _unmount(t);
            audio.dispose();
          }
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio partial save retries only its failed draft without replaying confirmed notifications',
      (t) async {
        size(t, const Size(1280, 1100));
        final notifications = NotificationMotionPort();
        final module = createNotificationSettingsModule(notifications);
        final port = _AudioPort()..saveFailure = const AudioFailure('conflict');
        final audio = NotificationAudioController(port);
        try {
          await module.initialize();
          await audio.refresh();
          await t.pumpWidget(
            scopedApp(
              SizedBox.expand(
                child: NotificationSettingsPage(module: module, audio: audio),
              ),
              suite,
            ),
          );
          await _frames(t);
          await _toggle(t);
          final windows = find
              .ancestor(
                of: find.byKey(const Key('notification-channel-windows')),
                matching: find.byType(StarBridgeSwitch),
              )
              .first;
          await t.ensureVisible(windows);
          await t.pump();
          await t.tap(windows);
          await _frames(t, count: 2);
          final drafts = _drafts(t);
          expect(drafts.dirty, isTrue);
          expect(port.saves, isEmpty);
          expect(notifications.writes, isEmpty);
          await _click(t, 'notification-save');
          await _frames(t);
          expect(notifications.writes, hasLength(1));
          expect(module.projection.value.revision, 12);
          expect(port.saves, hasLength(1));
          expect(audio.value!.revision, 3);
          expect(audio.value!.enabled, isTrue);
          expect(drafts.dirty, isTrue);
          expect(drafts.failed, isTrue);
          expect(drafts.saving, isFalse);
          port.saveFailure = null;
          await _click(t, 'notification-save', source: 'keyboard');
          await _frames(t);
          expect(notifications.writes, hasLength(1));
          expect(notifications.reads, hasLength(1));
          expect(port.saves, hasLength(2));
          expect(port.saves.last.$1.revision, 3);
          expect(port.saves.last.$5, InteractionSource.keyboard);
          expect(audio.value!.revision, 4);
          expect(audio.value!.enabled, isFalse);
          expect(drafts.dirty, isFalse);
          expect(drafts.failed, isFalse);
          expect(port.previews, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          port.releaseAll();
          await _frames(t, count: 2);
          await _unmount(t);
          audio.dispose();
          module.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio preview uses confirmed settings rather than an unsaved desired switch and stop stays nonbusy',
      (t) async {
        size(t, const Size(1280, 1100));
        for (final savedEnabled in [true, false]) {
          final port = _AudioPort()
            ..value = AudioPreferences(
              3,
              savedEnabled,
              .65,
              true,
              doNotDisturb: true,
            );
          final audio = NotificationAudioController(port);
          try {
            await audio.refresh();
            await t.pumpWidget(_editorApp(audio, suite, Object()));
            await _frames(t);
            await _toggle(t);
            final drafts = _drafts(t);
            expect(drafts.dirty, isTrue);
            expect(t.widget<StarBridgeSwitch>(_switch()).value, !savedEnabled);
            expect(audio.value!.enabled, savedEnabled);
            expect(audio.value!.revision, 3);
            expect(port.saves, isEmpty);
            if (savedEnabled) {
              expect(_button(t, 'audio-preview').onActivate, isNotNull);
              await _click(t, 'audio-preview');
              await _frames(t);
              expect(port.previews, hasLength(1));
              expect(audio.status, 'played');
              expect(audio.busy, isFalse);
              final token = _busyFrame(t).doneToken;
              await _click(t, 'audio-stop');
              expect(port.stops, hasLength(1));
              expect(audio.status, 'stopped');
              expect(audio.busy, isFalse);
              expect(
                _busyFrame(t).doneToken,
                token,
                reason: 'Stop does not invent a new _run completion phase.',
              );
            } else {
              expect(_button(t, 'audio-preview').onActivate, isNull);
              await audio.preview();
              expect(port.previews, isEmpty);
            }
            expect(drafts.dirty, isTrue);
            expect(port.saves, isEmpty);
            expect(port.reads, hasLength(1));
            await _click(t, 'notification-discard');
            expect(drafts.dirty, isFalse);
            expect(audio.value!.enabled, savedEnabled);
            expect(port.saves, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            port.releaseAll();
            await _frames(t, count: 2);
            await _unmount(t);
            audio.dispose();
          }
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio already-busy attachment and replacement do not reread or accept old completion presentation',
      (t) async {
        size(t, const Size(1280, 1100));
        final oldPort = _AudioPort(), nextPort = _AudioPort();
        final oldAudio = NotificationAudioController(oldPort);
        final nextAudio = NotificationAudioController(nextPort);
        final oldRead = oldPort.holdRead(), nextRead = nextPort.holdRead();
        final oldRequest = oldAudio.refresh();
        final nextRequest = nextAudio.refresh();
        try {
          await t.pumpWidget(_panelApp(oldAudio, suite));
          await _frames(t, count: 2);
          expect(oldPort.reads, hasLength(1));
          expect(oldAudio.busy, isTrue);
          await t.pumpWidget(_panelApp(nextAudio, suite));
          await _frames(t, count: 2);
          expect(oldPort.stops, hasLength(1));
          expect(nextPort.reads, hasLength(1));
          expect(nextPort.stops, isEmpty);
          expect(nextAudio.value, isNull);
          final nextToken = _busyFrame(t).doneToken;
          oldRead.complete(oldPort.value);
          await oldRequest;
          await _frames(t);
          expect(nextAudio.busy, isTrue);
          expect(nextAudio.value, isNull);
          expect(_busyFrame(t).busy, isTrue);
          expect(_busyFrame(t).doneToken, nextToken);
          expect(nextPort.reads, hasLength(1));
          expect(nextPort.saves, isEmpty);
          expect(nextPort.previews, isEmpty);
          nextRead.complete(nextPort.value);
          await nextRequest;
          await _frames(t);
          expect(nextAudio.value, same(nextPort.value));
          expect(nextAudio.busy, isFalse);
          expect(_busyFrame(t).doneToken, isNot(nextToken));
          expect(t.takeException(), isNull);
        } finally {
          oldPort.releaseAll();
          nextPort.releaseAll();
          await _frames(t, count: 2);
          await _unmount(t);
          oldAudio.dispose();
          nextAudio.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio preview restrictions stop lifecycle and unmount preserve the original preview epoch',
      (t) async {
        size(t, const Size(1280, 1100));
        for (final unavailable in [
          const AudioPreferences(3, false, .65, true),
          const AudioPreferences(3, true, 0, true),
          const AudioPreferences(3, true, .65, false),
        ]) {
          final blockedPort = _AudioPort()..value = unavailable;
          final blocked = NotificationAudioController(blockedPort);
          try {
            await blocked.refresh();
            await t.pumpWidget(_panelApp(blocked, suite));
            await _frames(t, count: 2);
            expect(_button(t, 'audio-preview').onActivate, isNull);
            await blocked.preview();
            expect(blockedPort.previews, isEmpty);
            expect(blockedPort.saves, isEmpty);
          } finally {
            await _unmount(t);
            blocked.dispose();
          }
        }
        final port = _AudioPort();
        final audio = NotificationAudioController(port);
        try {
          await audio.refresh();
          await t.pumpWidget(_panelApp(audio, suite));
          await _frames(t);
          final preview = port.holdPreview();
          await _click(t, 'audio-preview');
          expect(port.previews, hasLength(1));
          expect(audio.busy, isTrue);
          expect(_button(t, 'audio-preview').onActivate, isNull);
          await audio.preview();
          expect(port.previews, hasLength(1));
          final token = _busyFrame(t).doneToken;
          await audio.stop();
          await _frames(t, count: 2);
          expect(port.stops, hasLength(1));
          expect(audio.status, 'stopped');
          expect(
            audio.busy,
            isTrue,
            reason: 'stop never cancels or replaces the existing _run busy operation.',
          );
          expect(_busyFrame(t).doneToken, token);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          await _frames(t, count: 2);
          expect(port.stops, hasLength(2));
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await _frames(t, count: 2);
          expect(port.stops, hasLength(2));
          await _unmount(t);
          expect(port.stops, hasLength(3));
          preview.complete('played');
          await _frames(t);
          expect(audio.status, 'stopped');
          expect(audio.busy, isFalse);
          expect(port.saves, isEmpty);
          expect(port.reads, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          port.releaseAll();
          await _frames(t, count: 2);
          await _unmount(t);
          audio.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio frame owner and session retirement do not acknowledge or replay old pending drafts',
      (t) async {
        size(t, const Size(1280, 1100));
        for (final replaceSession in [false, true]) {
          final port = _AudioPort();
          final audio = NotificationAudioController(port);
          final pair1 = InMemoryBridgeConnection.createPair();
          final pair2 = InMemoryBridgeConnection.createPair();
          final firstSession = BridgeClientSession(
            connection: pair1.client,
            sessionGeneration: 1,
          );
          final nextSession = BridgeClientSession(
            connection: pair2.client,
            sessionGeneration: 2,
          );
          final owner = Object();
          try {
            await audio.refresh();
            await t.pumpWidget(
              _editorApp(
                audio,
                suite,
                owner,
                session: replaceSession ? firstSession : null,
              ),
            );
            await _frames(t);
            final staleChange = t
                .widget<StarBridgeSwitch>(_switch())
                .onChanged!;
            await _toggle(t);
            final retired = _drafts(t);
            final staleSave = _button(t, 'notification-save').onActivate!;
            expect(retired.dirty, isTrue);
            expect(port.saves, isEmpty);
            final saving = port.holdSave();
            await _click(t, 'notification-save');
            expect(retired.saving, isTrue);
            expect(port.saves, hasLength(1));
            await t.pumpWidget(
              _editorApp(
                audio,
                suite,
                replaceSession ? owner : Object(),
                session: replaceSession ? nextSession : null,
              ),
            );
            await _frames(t, count: 2);
            final fresh = _drafts(t);
            expect(fresh, isNot(same(retired)));
            expect(fresh.dirty, isFalse);
            expect(fresh.saving, isFalse);
            staleChange(false);
            staleSave(InteractionSource.keyboard);
            expect(port.saves, hasLength(1));
            expect(port.reads, hasLength(1));
            expect(port.stops, isNotEmpty);
            port.accept(saving);
            await _frames(t);
            expect(
              audio.value!.enabled,
              isFalse,
              reason: 'Retiring UI drafts does not cancel an accepted local owner write.',
            );
            expect(audio.value!.revision, 4);
            expect(fresh.dirty, isFalse);
            expect(fresh.failed, isFalse);
            expect(fresh.saving, isFalse);
            expect(port.saves, hasLength(1));
            expect(port.previews, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            port.releaseAll();
            await _frames(t, count: 2);
            await _unmount(t);
            audio.dispose();
            await t.runAsync(() async {
              await firstSession.close();
              await nextSession.close();
              await pair1.host.close();
              await pair2.host.close();
            });
          }
        }
      },
      timeout: _timeout,
    );
  }
}
