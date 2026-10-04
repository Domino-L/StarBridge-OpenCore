import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_settings.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';

import 'menu_room_management_test.dart' show RoomPort;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

Map<String, Object?> settings() => {
  'title': 'Updated room',
  'goal': 'Test',
  'capacity': 6,
  'isPublic': true,
  'eligibility': 'everyone',
  'admissionMode': 'approval',
  'passwordMode': 'keep',
  'password': '',
  'voiceRequirement': 'recommended',
  'language': 'zh',
  'autoDisbandHours': 6,
  'recruitmentDurationMinutes': null,
  'gameplayTagNodeIds': ['combat'],
  'contextTagIds': <String>[],
};

class SettingsPort extends RoomPort {
  String status = 'updated';
  bool readUnavailable = false;
  String roomId = 'private-room';
  Duration nextDelay = Duration.zero;
  Completer<RoomCommandResult>? pendingResult;
  @override
  Future<RoomReadResult> read() async {
    final delay = nextDelay;
    nextDelay = Duration.zero;
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (readUnavailable) return const RoomReadResult(RoomReadState.unavailable);
    final base = (await super.read()).directory!;
    final room = base.rooms.single;
    const tag = RoomTag(id: 'combat', text: '战斗', isGameplay: true);
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        currentRoomId: base.currentRoomId == null ? null : roomId,
        serverTime: base.serverTime,
        tagOptions: const [tag],
        rooms: [
          PartyRoom(
            id: roomId,
            title: room.title,
            goal: room.goal,
            capacity: room.capacity,
            isPublic: room.isPublic,
            eligibility: room.eligibility,
            admissionMode: room.admissionMode,
            passwordRequired: room.passwordRequired,
            voice: 'recommended',
            language: room.language,
            expiresAt: room.expiresAt,
            recruitmentClosesAt: room.recruitmentClosesAt,
            viewerIsHost: room.viewerIsHost,
            members: room.members,
            tags: const [tag],
          ),
        ],
      ),
    );
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    calls.add(command);
    if (pendingResult != null) return pendingResult!.future;
    return RoomCommandResult(
      status,
      error: status == 'unknown' ? 'outcomeUnknown' : null,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'read failure before save remains unavailable, not a host rejection',
    (tester) async {
      final port = SettingsPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final action = MenuFeatureView.parse(views.last).room!.settings!.action!;
      port.readUnavailable = true;
      session.act(action, jsonEncode({'request': 'q1', 'data': settings()}));
      await tester.pump();
      expect(port.calls, isEmpty);
      final reply = views
          .map(MenuFeatureView.parse)
          .map((v) => v.room?.settings?.reply)
          .whereType<Map<String, Object?>>()
          .last;
      expect(reply['error'], 'unavailable');
      session.dispose();
    },
  );
  for (final transition in ['room', 'hidden']) {
    testWidgets(
      'late settings receipt after outer timeout cannot affect $transition',
      (tester) async {
        final port = SettingsPort(), views = <Map<String, Object?>>[];
        final session = MenuRoomsSession(port, views.add)..show(true);
        await tester.pump();
        final action = MenuFeatureView.parse(views.last)
            .room!
            .settings!
            .action!;
        port.nextDelay = const Duration(seconds: 8);
        port.pendingResult = Completer<RoomCommandResult>();
        session.act(action, jsonEncode({'request': 'q1', 'data': settings()}));
        await tester.pump(const Duration(seconds: 8));
        expect(port.calls.length, 1);
        await tester.pump(const Duration(seconds: 8));
        if (transition == 'hidden') {
          session.show(false);
        } else {
          port.roomId = 'other-private-room';
          await session.refresh();
        }
        final before = jsonEncode(session.currentView);
        port.pendingResult!.complete(const RoomCommandResult('updated'));
        await tester.pump();
        expect(jsonEncode(session.currentView), before);
        expect(port.calls.length, 1);
        session.dispose();
      },
    );
  }
  testWidgets('settings use opaque action and revalidate host before update', (
    tester,
  ) async {
    final port = SettingsPort(), views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    final view = MenuFeatureView.parse(views.last);
    final action = view.room!.settings!.action!;
    expect(jsonEncode(views.last), isNot(contains('private-room')));
    session.act(action, jsonEncode({'request': 'q1', 'data': settings()}));
    await tester.pump();
    expect(port.calls.single.operation, RoomOperation.update);
    expect(port.calls.single.data['roomId'], 'private-room');
    expect(port.calls.single.data['passwordMode'], 'keep');
    expect(
      MenuFeatureView.parse(views.last).room!.settings!.reply!['status'],
      'updated',
    );
    session.act(action, jsonEncode({'request': 'q2', 'data': settings()}));
    await tester.pump();
    expect(port.calls.length, 1);
    session.dispose();
  });
  for (final mode in [
    'hostLost',
    'left',
    'capabilityLost',
    'rawId',
    'extraField',
    'invalidated',
  ]) {
    testWidgets('settings reject $mode', (tester) async {
      final port = SettingsPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final action = MenuFeatureView.parse(views.last).room!.settings!.action!;
      if (mode == 'hostLost') port.host = false;
      if (mode == 'left') port.joined = false;
      if (mode == 'capabilityLost') port.supportsManagement = false;
      if (mode == 'invalidated') port.changes.add(null);
      session.act(
        action,
        jsonEncode({
          'request': 'q1',
          'data': {
            ...settings(),
            if (mode == 'rawId') 'roomId': 'private-room',
            if (mode == 'extraField') 'operation': 'close',
          },
        }),
      );
      await tester.pump();
      expect(port.calls, isEmpty);
      session.dispose();
    });
  }
  testWidgets(
    'unknown settings cannot replay or expose another settings action',
    (tester) async {
      final port = SettingsPort()..status = 'unknown',
          views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      final action = MenuFeatureView.parse(views.last).room!.settings!.action!;
      session.act(action, jsonEncode({'request': 'q1', 'data': settings()}));
      await tester.pump();
      expect(MenuFeatureView.parse(views.last).room!.settings!.action, isNull);
      session.act(action, jsonEncode({'request': 'q1', 'data': settings()}));
      await tester.pump();
      expect(port.calls.length, 1);
      session.dispose();
    },
  );
  testWidgets(
    'settings port strips display id and handles explicit action rejection immediately',
    (tester) async {
      final source = SettingsPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(source, views.add)..show(true);
      await tester.pump();
      final view = MenuFeatureView.parse(views.last);
      String? dispatched;
      final port = MenuRoomSettingsPort(view, (_, value) => dispatched = value);
      final result = port.execute(
        RoomCommand(RoomOperation.update, {
          ...settings(),
          'roomId': view.scope,
        }),
      );
      expect(
        (jsonDecode(dispatched!) as Map)['data'],
        isNot(contains('roomId')),
      );
      port.update(
        MenuFeatureView.parse({
          ...views.last,
          'rejectedAction': view.room!.settings!.action,
        }),
      );
      expect((await result).status, 'rejected');
      await port.close();
      session.dispose();
    },
  );
  testWidgets(
    'client editor remains open with draft during menu refresh; cancel writes nothing',
    (tester) async {
      size(tester, const Size(1000, 900));
      final port = SettingsPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      Widget panel() => app(
        MenuRoomsPanel(
          view: MenuFeatureView.parse(views.last),
          onAction: session.act,
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('rooms.browse'), findsNothing);
      expect(find.text('房间资料'), findsWidgets);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-room-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final title = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          )
          .first;
      await tester.enterText(title, 'Keep draft');
      await session.refresh(silent: true);
      await tester.pumpWidget(panel());
      await tester.pump();
      expect(find.text('Keep draft'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(port.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  for (final outcome in ['updated', 'unknown']) {
    testWidgets('full menu editor save chain returns $outcome once', (
      tester,
    ) async {
      size(tester, const Size(1280, 900));
      final port = SettingsPort()..status = outcome;
      final frame = ValueNotifier<MenuFeatureView>(
        const MenuFeatureView('loading'),
      );
      final session = MenuRoomsSession(
        port,
        (raw) => frame.value = MenuFeatureView.parse(raw),
      )..show(true);
      await tester.pump();
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: ValueListenableBuilder<MenuFeatureView>(
              valueListenable: frame,
              builder: (_, view, _) =>
                  MenuRoomsPanel(view: view, onAction: session.act),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-room-settings')));
      await tester.pumpAndSettle();
      final editor = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          )
          .first;
      await tester.enterText(editor, 'Updated room');
      await capture(tester, key, 'menu-room-settings-1280');
      size(tester, const Size(1440, 900));
      await tester.pumpAndSettle();
      await capture(tester, key, 'menu-room-settings-1440');
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(FilledButton),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(port.calls.length, 1);
      expect(port.calls.single.data['title'], 'Updated room');
      expect(port.calls.single.data['passwordMode'], 'remove');
      expect(frame.value.room!.settings!.reply!['status'], outcome);
      if (outcome == 'updated') {
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('房间设置已保存。'), findsOneWidget);
      } else {
        expect(frame.value.notice, contains('保存结果未确认'));
        expect(frame.value.room!.settings!.action, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      frame.dispose();
    });
  }
  for (final change in [
    'permission',
    'scope',
    'permission-picker',
    'scope-picker',
  ]) {
    testWidgets('open menu editor is retired after $change change', (
      tester,
    ) async {
      size(tester, const Size(1000, 900));
      final port = SettingsPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      Widget panel() => app(
        MenuRoomsPanel(
          view: MenuFeatureView.parse(views.last),
          onAction: session.act,
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-room-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      if (change.endsWith('picker')) {
        await tester.ensureVisible(find.byKey(const Key('room-choose-tags')));
        await tester.tap(find.byKey(const Key('room-choose-tags')));
        await tester.pumpAndSettle();
        expect(find.text('确认标签'), findsOneWidget);
      }
      if (change.startsWith('permission')) {
        port.host = false;
        await session.refresh(silent: true);
      } else {
        port.changes.add(null);
        await tester.pump();
      }
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(port.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }
}
