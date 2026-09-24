import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_notification_settings_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;

class AudioFake implements NotificationAudioPort {
  AudioPreferences value = const AudioPreferences(0, false, .65, true);
  int plays = 0, stops = 0, writes = 0;
  bool fail = false;
  Completer<AudioPreferences>? delayed;
  Completer<String>? delayedPreview;
  @override
  Future<AudioPreferences> read() async => value;
  @override
  Future<AudioPreferences> save(
    AudioPreferences current,
    bool enabled,
    double volume, {
    bool? doNotDisturb,
  }) async {
    writes++;
    if (fail) throw const AudioFailure('conflict');
    if (delayed != null) return delayed!.future;
    return value = AudioPreferences(
      current.revision + 1,
      enabled,
      volume,
      true,
      doNotDisturb: doNotDisturb ?? current.doNotDisturb,
    );
  }

  @override
  Future<String> preview() async {
    plays++;
    return delayedPreview == null ? 'played' : delayedPreview!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  setUpAll(loadFonts);
  test('a late preview reply cannot undo stopping on page exit', () async {
    final port = AudioFake();
    final audio = NotificationAudioController(port);
    addTearDown(audio.dispose);
    await audio.refresh();
    await audio.save(enabled: true);
    port.delayedPreview = Completer<String>();
    final pending = audio.preview();
    await audio.stop();
    port.delayedPreview!.complete('played');
    await pending;
    expect(audio.status, 'stopped');
    expect(port.stops, 1);
  });
  test(
    'mute, zero gain, failed save and duplicate command protection',
    () async {
      final port = AudioFake();
      final audio = NotificationAudioController(port);
      addTearDown(audio.dispose);
      await audio.refresh();
      await audio.preview();
      expect(port.plays, 0);
      await audio.save(enabled: true, volume: 0);
      await audio.preview();
      expect(port.plays, 0);
      await audio.save(volume: .3);
      await audio.preview();
      expect(port.plays, 1);
      port.fail = true;
      await audio.save(enabled: false);
      expect(audio.value!.enabled, isTrue);
      expect(audio.error, 'conflict');
      port.fail = false;
      port.delayed = Completer<AudioPreferences>();
      final saving = audio.save(volume: .2);
      final count = port.writes;
      await audio.save(volume: .1);
      expect(port.writes, count);
      port.delayed!.complete(const AudioPreferences(3, true, .2, true));
      await saving;
      expect(audio.value!.volume, .2);
    },
  );
  test(
    'Bridge audio stays account-agnostic and rejects malformed confirmation',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      session.acceptHostCapabilities([
        'notificationAudio.read',
        'notificationAudio.save',
        'notificationAudio.preview',
        'notificationAudio.stop',
      ]);
      final requests = <BridgeEnvelope>[];
      var malformed = false;
      final sub = pair.host.incoming.listen((r) {
        requests.add(r);
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: r.name,
              correlationId: r.correlationId,
              sessionGeneration: r.sessionGeneration,
              status: 'ok',
              payload: r.name == 'notificationAudio.preview'
                  ? {
                      'schemaVersion': 1,
                      'status': 'played',
                      'cueId': 'notify.soft',
                    }
                  : {
                      'schemaVersion': 1,
                      'revision': 1,
                      'enabled': true,
                      'volume': malformed ? -1 : .5,
                      'previewAvailable': true,
                    },
            ),
          ),
        );
      });
      final port = BridgeNotificationAudio(session);
      final read = await port.read();
      expect(read.volume, .5);
      await port.save(read, false, .25);
      await port.preview();
      expect(
        requests.every(
          (r) => r.accountContext == null && r.sessionGeneration == 3,
        ),
        isTrue,
      );
      expect(requests[1].payload, {
        'schemaVersion': 1,
        'expectedRevision': 1,
        'enabled': false,
        'volume': .25,
        'doNotDisturb': false,
      });
      malformed = true;
      await expectLater(port.read(), throwsA(isA<AudioFailure>()));
      await sub.cancel();
      await session.close();
      await pair.host.close();
    },
  );
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'audio is usable without remote notification settings at $width',
      (tester) async {
        size(tester, Size(width, 850));
        final port = AudioFake()
          ..value = const AudioPreferences(
            0,
            false,
            .65,
            true,
            doNotDisturb: true,
          );
        final audio = NotificationAudioController(port);
        final settings = createNotificationSettingsModule(
          HostUnavailableNotificationSettingsAdapter(),
        );
        await settings.initialize();
        await tester.pumpWidget(
          app(NotificationSettingsPage(module: settings, audio: audio)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NotificationAudioPanel), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '试听普通通知'))
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const Key('audio-enabled')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('audio-dnd')), findsNothing);
        expect(find.text('自动播放通知声音'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(NotificationAudioPanel),
            matching: find.byType(SwitchListTile),
          ),
          findsOneWidget,
        );
        expect(port.writes, 0);
        await tester.tap(find.byKey(const Key('notification-save')));
        await tester.pumpAndSettle();
        expect(port.writes, 1);
        await tester.ensureVisible(find.text('试听普通通知'));
        await tester.tap(find.text('试听普通通知'));
        await tester.pumpAndSettle();
        expect(port.plays, 1);
        expect(find.text('已开始试听'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('audio-enabled')));
        await tester.tap(find.byKey(const Key('audio-enabled')));
        await tester.pumpAndSettle();
        expect(port.value.enabled, isTrue);
        await tester.tap(find.byKey(const Key('notification-save')));
        await tester.pumpAndSettle();
        expect(port.value.enabled, isFalse);
        expect(audio.canPreview, isFalse);
        if (const bool.fromEnvironment('AUDIO_CAPTURE')) {
          await expectLater(
            find.byType(NotificationSettingsPage),
            matchesGoldenFile('../../../build/audio-settings-$width.png'),
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(port.stops, greaterThan(0));
        audio.dispose();
        settings.dispose();
      },
    );
  }
}
