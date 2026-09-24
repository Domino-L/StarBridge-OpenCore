import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/local_notification_listener.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';

import 'notification_audio_test.dart' show AudioFake;

import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';

import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;

class Fixture {
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 3,
  );
  late final adapter = BridgeNotificationSettingsAdapter(session);
  late final module = createNotificationSettingsModule(adapter);
  late StreamSubscription<BridgeEnvelope> subscription;
  bool fail = false, malformed = false, otherOwner = false;
  final requests = <BridgeEnvelope>[];
  Map<String, Object?> value = {
    'schemaVersion': 1,
    'revision': 0,
    'inAppEnabled': true,
    'windowsEnabled': false,
    'position': 'topRight',
    'preview': 'sourceOnly',
  };
  Future<void> start() async {
    session.acceptHostCapabilities([
      'notificationSettings.read',
      'notificationSettings.save',
      'partyRooms.read',
    ]);
    subscription = pair.host.incoming.listen((r) {
      requests.add(r);
      if (r.name == 'notificationSettings.save' && !fail) {
        value = {
          'schemaVersion': 1,
          'revision': (value['revision']! as int) + 1,
          'inAppEnabled': r.payload['inAppEnabled'],
          if (r.payload.containsKey('windowsEnabled'))
            'windowsEnabled': r.payload['windowsEnabled'],
          if (r.payload.containsKey('overlayEnabled'))
            'overlayEnabled': r.payload['overlayEnabled'],
          if (r.payload.containsKey('directMessageWindowsEnabled'))
            'directMessageWindowsEnabled': r.payload['directMessageWindowsEnabled'],
          'position': r.payload['position'],
          'preview': r.payload['preview'],
        };
      }
      final accountCall =
          r.name == 'account.getCurrent' || r.name == 'partyRooms.getDirectory';
      final account = accountCall
          ? BridgeAccountContext(
              environment: 'test',
              authority: 'scm',
              subject: otherOwner && r.name != 'account.getCurrent'
                  ? 'two'
                  : 'one',
            )
          : null;
      final payload = r.name == 'account.getCurrent'
          ? <String, Object?>{'schemaVersion': 1, 'state': 'signedIn'}
          : r.name == 'partyRooms.getDirectory'
          ? <String, Object?>{
              'schemaVersion': 1,
              'serverTime': '2026-01-01T00:00:00Z',
              'currentRoomId': null,
              'rooms': [],
              'receivedInvitations': [],
              'tagOptions': [],
              'localReminder': {
                'schemaVersion': 1,
                'revision': value['revision'],
                'invitations': 1,
                'applications': 0,
              },
            }
          : malformed
          ? <String, Object?>{}
          : value;
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: r.name,
            correlationId: r.correlationId,
            sessionGeneration: 3,
            accountContext: account,
            status: fail ? 'error' : 'ok',
            payload: payload,
            error: fail
                ? const BridgeErrorBody(
                    code: 'notificationSettings.write_conflict',
                    message: 'Conflict',
                    retryable: false,
                  )
                : null,
          ),
        ),
      );
    });
    await module.initialize();
  }

  Future<void> close() async {
    module.dispose();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  setUpAll(loadFonts);
  test('private desktop preference is optional and persists only after save', () async {
    final f = Fixture()..value['directMessageWindowsEnabled'] = false;
    await f.start();
    addTearDown(f.close);
    final current = f.module.projection.value.settings!;
    expect(current.directMessageDeliveryAvailable, isTrue);
    final edited = current.copyWith(channels: current.channels.copyWith(directMessageWindowsEnabled: true));
    expect(f.requests.where((r) => r.name.endsWith('.save')), isEmpty);
    expect(await f.module.save(edited), isTrue);
    expect(f.value['directMessageWindowsEnabled'], isTrue);
    await f.module.refresh();
    expect(f.module.projection.value.settings!.channels.directMessageWindowsEnabled, isTrue);
  });
  test(
    'normal settings bridge confirms local values and keeps failed saves',
    () async {
      final f = Fixture();
      await f.start();
      addTearDown(f.close);
      expect(f.module.projection.value.settings!.localInAppOnly, isTrue);
      final edited = f.module.projection.value.settings!.copyWith(
        previewMode: NotificationPreviewMode.hiddenDetails,
      );
      expect(await f.module.save(edited), isTrue);
      expect(f.requests.every((r) => r.accountContext == null), isTrue);
      expect(f.value['preview'], 'hiddenDetails');
      f.fail = true;
      expect(
        await f.module.save(
          edited.copyWith(previewMode: NotificationPreviewMode.fullContent),
        ),
        isFalse,
      );
      expect(
        f.module.projection.value.settings!.previewMode,
        NotificationPreviewMode.hiddenDetails,
      );
      f.fail = false;
      f.malformed = true;
      await f.module.refresh();
      expect(
        f.module.projection.value.availability,
        NotificationSettingsAvailability.unavailable,
      );
    },
  );
  test('real room adapter forwards scoped reminders with value-based account matching', () async {
    final f = Fixture();
    await f.start();
    addTearDown(f.close);
    final seen = <LocalRoomReminder?>[];
    final sub = f.adapter.reminders.listen(seen.add);
    addTearDown(sub.cancel);
    final rooms = BridgePartyRoomsAdapter(
      f.session,
      onReminder: f.adapter.onRoomReminder,
    );
    addTearDown(rooms.close);
    expect((await rooms.read()).state, RoomReadState.ready);
    expect(seen.single!.invitations, 1);
    f.otherOwner = true;
    await rooms.read();
    expect(seen, hasLength(1));
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets('normal reminder settings expose working controls at $width', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      final f = Fixture();
      f.value['overlayEnabled'] = true;
      await f.start();
      addTearDown(f.close);
      final audio = NotificationAudioController(AudioFake());
      addTearDown(audio.dispose);
      await tester.pumpWidget(
        app(
          NotificationSettingsPage(
            module: f.module,
            audio: audio,
            desktop: const RunnerDesktopNotificationPort(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notification-settings-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('notification-channel-in-app')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notification-channel-windows')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notification-source-rules-panel')),
        findsNothing,
      );
      expect(find.text('账号同步'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('notification-channel-in-app')),
      );
      await tester.tap(find.byKey(const Key('notification-channel-in-app')));
      await tester.pumpAndSettle();
      expect(f.value['inAppEnabled'], true);
      await tester.ensureVisible(
        find.byKey(const Key('notification-channel-windows')),
      );
      await tester.tap(find.byKey(const Key('notification-channel-windows')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-save')));
      await tester.pumpAndSettle();
      expect(f.value['inAppEnabled'], false);
      expect(f.value['windowsEnabled'], true);
      expect(
        find.byKey(const Key('notification-desktop-test')),
        findsOneWidget,
      );
      final choice = find.byKey(
        const Key('notification-preview-hiddenDetails'),
      );
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-save')));
      await tester.pumpAndSettle();
      expect(f.value['preview'], 'hiddenDetails');
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('NOTIFICATION_CAPTURE')) {
        await tester.ensureVisible(find.text('通知与提醒'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(NotificationSettingsPage),
          matchesGoldenFile('../../../build/notification-local-$width.png'),
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'delivery obeys preview, mute, revision and foreground without replay',
    (tester) async {
      size(tester, const Size(1200, 800));
      final f = Fixture();
      await f.start();
      addTearDown(f.close);
      await tester.pumpWidget(
        app(
          LocalNotificationListener(
            events: f.adapter.reminders,
            settings: f.module,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void emit([int? revision]) => f.adapter.onRoomReminder({
        'schemaVersion': 1,
        'revision': revision ?? f.value['revision'],
        'invitations': 2,
        'applications': 1,
      });
      final toast = find.byKey(const Key('starbridge-notification-toast'));
      emit();
      await tester.pumpAndSettle();
      expect(toast, findsOneWidget);
      expect(find.text('有新的房间消息，请前往房间查看。'), findsOneWidget);
      await f.module.save(
        f.module.projection.value.settings!.copyWith(
          previewMode: NotificationPreviewMode.fullContent,
        ),
      );
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
      emit();
      await tester.pumpAndSettle();
      expect(find.textContaining('2 个新邀请、1 个新加入申请'), findsOneWidget);
      await f.module.save(
        f.module.projection.value.settings!.copyWith(
          previewMode: NotificationPreviewMode.hiddenDetails,
        ),
      );
      emit();
      await tester.pumpAndSettle();
      expect(find.text('新通知'), findsOneWidget);
      expect(find.text('房间提醒'), findsNothing);
      for (final position in DesktopNotificationPosition.values) {
        final value = f.module.projection.value.settings!;
        await f.module.save(
          value.copyWith(
            channels: value.channels.copyWith(desktopPosition: position),
          ),
        );
        emit();
        await tester.pumpAndSettle();
        final center = tester.getCenter(toast);
        expect(
          center.dx > 600,
          position == DesktopNotificationPosition.topRight ||
              position == DesktopNotificationPosition.bottomRight,
        );
        expect(
          center.dy > 400,
          position == DesktopNotificationPosition.bottomLeft ||
              position == DesktopNotificationPosition.bottomRight,
        );
      }
      await f.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'bootstrap.invalidated',
          sessionGeneration: 3,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
      emit(0);
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      emit();
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
      final current = f.module.projection.value.settings!;
      await f.module.save(
        current.copyWith(
          channels: current.channels.copyWith(inAppEnabled: false),
        ),
      );
      emit();
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
