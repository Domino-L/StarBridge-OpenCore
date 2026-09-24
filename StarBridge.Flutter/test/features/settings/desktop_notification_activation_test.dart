import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_activity_page.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/features/settings/desktop_notification_test_button.dart';
import 'package:starbridge_flutter/platform/host/desktop_notification_port.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import 'desktop_notification_test.dart' show DesktopFake;
import '../friends/social_layout_test.dart' show app, loadFonts;
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';

class _DirectDesktop extends _Desktop implements DesktopNotificationDestinationPort {
  String destination = 'directMessages';
  @override
  Future<String?> consumeDestination(DesktopReminderActivation value) async =>
      valid && isCurrent(value) ? destination : null;
}

class _Desktop extends DesktopFake
    implements
        DesktopNotificationActivationPort,
        DesktopNotificationDiagnostics {
  final clicks = StreamController<DesktopReminderActivation>.broadcast();
  int generation = 1;
  bool valid = true;
  @override
  Stream<DesktopReminderActivation> get activations => clicks.stream;
  @override
  bool isCurrent(DesktopReminderActivation value) =>
      value.generation == generation;
  @override
  Future<bool> consume(DesktopReminderActivation value) async =>
      valid && isCurrent(value);
  @override
  Future<DesktopNotificationTestResult> testDesktop() async =>
      const DesktopNotificationTestResult(false, 'doNotDisturb');
}

class _Rooms implements PartyRoomsPort {
  final example = ExamplePartyRoomsAdapter();
  Completer<RoomReadResult>? pending;
  int reads = 0;
  @override
  Future<RoomReadResult> read() {
    reads++;
    return pending?.future ?? example.read();
  }

  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<void> close() async {
    await example.close();
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets('organization notification opens directory without room reads', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = _DirectDesktop()..destination = 'communities';
    final rooms = _Rooms();
    final composition = AppComposition.forTest(windowChrome: InMemoryWindowChrome(),
        desktopNotifications: desktop, partyRoomsPort: rooms);
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    final reads = rooms.reads;
    desktop.clicks.add(DesktopReminderActivation('c' * 32, 1));
    await tester.pumpAndSettle();
    expect(find.byType(CommunitiesPage), findsOneWidget);
    expect(find.byType(RoomActivityPage), findsNothing);
    expect(rooms.reads, reads);
    await tester.pumpWidget(const SizedBox());
    await desktop.clicks.close();
  });
  testWidgets('private notification opens inbox without refreshing room activity', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = _DirectDesktop();
    final rooms = _Rooms();
    final composition = AppComposition.forTest(windowChrome: InMemoryWindowChrome(),
        desktopNotifications: desktop, partyRoomsPort: rooms);
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    final reads = rooms.reads;
    desktop.clicks.add(DesktopReminderActivation('b' * 32, 1));
    await tester.pumpAndSettle();
    expect(find.byType(DirectMessagesPage), findsOneWidget);
    expect(rooms.reads, reads);
    await tester.pumpWidget(const SizedBox());
    await desktop.clicks.close();
  });
  test(
    'notification refresh waits for background read and then reads afresh',
    () async {
      final port = _Rooms()..pending = Completer<RoomReadResult>();
      final module = PartyRoomsModule(port);
      final background = module.refresh();
      final fresh = module.refreshForNotification();
      expect(port.reads, 1);
      final pending = port.pending!;
      port.pending = null;
      pending.complete(await port.example.read());
      await background;
      expect(await fresh, isTrue);
      expect(port.reads, 2);
      module.dispose();
    },
  );
  testWidgets('native suppression reason is readable and does not resubmit', (
    tester,
  ) async {
    final port = _Desktop();
    await tester.pumpWidget(
      app(DesktopNotificationTestButton(port: port, enabled: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-desktop-test')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Windows 免打扰已开启'), findsOneWidget);
    expect(port.shown, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await port.clicks.close();
  });

  for (final scenario in ['valid', 'revoked', 'changedAccount']) {
    testWidgets('desktop click navigation: $scenario', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = _Desktop()..valid = scenario != 'revoked';
      final rooms = _Rooms();
      final composition = AppComposition.forTest(
        windowChrome: InMemoryWindowChrome(),
        desktopNotifications: desktop,
        partyRoomsPort: rooms,
      );
      await tester.pumpWidget(StarBridgeApp(composition: composition));
      await tester.pumpAndSettle();
      final initialReads = rooms.reads;
      if (scenario == 'changedAccount') {
        rooms.pending = Completer<RoomReadResult>();
      }
      desktop.clicks.add(DesktopReminderActivation('a' * 32, 1));
      await tester.pump();
      if (scenario == 'changedAccount') {
        desktop.generation++;
        rooms.pending!.complete(await rooms.example.read());
      }
      await tester.pumpAndSettle();
      expect(
        find.byType(NotificationInboxPage),
        scenario == 'valid' ? findsOneWidget : findsNothing,
      );
      if (scenario == 'valid') expect(rooms.reads, greaterThan(initialReads));
      if (scenario == 'revoked') {
        expect(find.textContaining('暂时无法打开这条提醒'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await desktop.clicks.close();
    });
  }
}
