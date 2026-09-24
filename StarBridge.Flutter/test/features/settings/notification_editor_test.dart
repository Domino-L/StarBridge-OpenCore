import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_dialog.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';

import 'notification_audio_test.dart' show AudioFake;
import 'player_activity_test.dart' show data;
import 'local_privacy_page_test.dart' show app, viewport;

void main() {
  testWidgets('partial save retains audio only; discard and leave guard work', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final adapter = InMemoryNotificationSettingsAdapter.forReview();
    final module = createNotificationSettingsModule(adapter);
    final port = AudioFake()..fail = true;
    final audio = NotificationAudioController(port);
    await module.initialize();
    await audio.refresh();
    await tester.pumpWidget(
      app(NotificationSettingsPage(module: module, audio: audio)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('audio-enabled')));
    final windows = find.byKey(const Key('notification-channel-windows'));
    await tester.ensureVisible(windows);
    await tester.tap(windows);
    await tester.pumpAndSettle();
    expect(adapter.current.revision, 11);
    expect(port.writes, 0);
    await tester.tap(find.byKey(const Key('notification-save')));
    await tester.pumpAndSettle();
    expect(adapter.current.revision, 12);
    expect(port.writes, 1);
    port.fail = false;
    await tester.tap(find.byKey(const Key('notification-save')));
    await tester.pumpAndSettle();
    expect(adapter.current.revision, 12);
    expect(port.writes, 2);
    expect(port.value.enabled, isTrue);
    await tester.ensureVisible(windows);
    await tester.tap(windows);
    await tester.pumpAndSettle();
    final leaving = confirmNotificationLeave(module);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-leave-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('notification-leave-discard')));
    await tester.pumpAndSettle();
    expect(await leaving, isTrue);
    expect(adapter.current.revision, 12);
    await tester.pumpWidget(const SizedBox());
    audio.dispose();
    module.dispose();
  });

  testWidgets('activity and play edits are staged and committed together', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1300));
    final calls = <String>[];
    final activity = PlayerActivityController((name, payload) async {
      calls.add(name);
      return {
        ...data(),
        if (name.endsWith('save')) ...{
          'enabled': payload['enabled'],
          'position': payload['position'],
        },
      };
    }, generation: () => 1);
    final port = _PlayPort();
    final play = ContinuousPlayController(port);
    final owner = Object();
    await tester.pumpWidget(
      app(
        NotificationEditorFrame(
          owner: owner,
          child: SingleChildScrollView(
            child: Column(
              children: [
                PlayerActivityConnectedPanel(
                  controller: activity,
                  showClose: false,
                ),
                ContinuousPlayConnectedPanel(controller: play),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final active = find.byKey(
      const Key('notification-player-activity-enabled'),
    );
    await tester.ensureVisible(active);
    await tester.tap(active);
    final remind = find.byKey(const Key('notification-play-enabled'));
    await tester.ensureVisible(remind);
    await tester.tap(remind);
    await tester.pumpAndSettle();
    expect(calls.where((name) => name.endsWith('save')), isEmpty);
    expect(port.writes, 0);
    await tester.tap(find.byKey(const Key('notification-save')));
    await tester.pumpAndSettle();
    expect(calls.where((name) => name.endsWith('save')).length, 1);
    expect(port.writes, 1);
    expect(port.value.enabled, false);
    await tester.pumpWidget(const SizedBox());
    activity.dispose();
    play.dispose();
  });
}

class _PlayPort implements ContinuousPlayPort {
  int writes = 0;
  ContinuousPlayValue value = const ContinuousPlayValue(
    enabled: true,
    firstMinutes: 60,
    repeatMinutes: 60,
    revision: 0,
  );
  @override
  Future<ContinuousPlayValue> read() async => value;
  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async {
    writes++;
    return value = ContinuousPlayValue(
      enabled: desired.enabled,
      firstMinutes: desired.firstMinutes,
      repeatMinutes: desired.repeatMinutes,
      revision: value.revision + 1,
    );
  }
}
