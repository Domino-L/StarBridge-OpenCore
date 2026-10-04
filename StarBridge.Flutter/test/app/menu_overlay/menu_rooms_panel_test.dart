import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_view.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/room_members_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/example_room_copy.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;

class RoomPort implements PartyRoomsPort, RoomChatProvider {
  String? selfAvatar;
  final source = ExamplePartyRoomsAdapter()..selectPreviewScene('host');
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  final Chat roomChat = Chat();
  @override
  Future<RoomReadResult> read() async {
    final result = await source.read();
    if (selfAvatar == null) return result;
    final d = result.directory!;
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        rooms: [
          for (final room in d.rooms)
            copyExampleRoom(
              room,
              members: [
                RoomMember(
                  callsign: 'Self',
                  gameId: 'Me',
                  isHost: true,
                  isSelf: true,
                  presence: '',
                  location: '',
                  ship: '',
                  shard: '',
                  avatarData: selfAvatar,
                ),
              ],
            ),
        ],
        currentRoomId: d.currentRoomId,
        serverTime: d.serverTime,
      ),
    );
  }

  @override
  Future<void> close() => changes.close();
}

class Chat implements RoomChatPort {
  int sends = 0;
  List<RoomChatMessage> messages = [];
  @override
  bool get available => true;
  @override
  Future<RoomChatPage> read(
    String roomId, {
    int after = 0,
    int before = 0,
  }) async => RoomChatPage(messages, messages.length, false);
  @override
  Future<RoomChatMessage> send(String roomId, String text) async {
    sends++;
    return RoomChatMessage(
      sequence: sends,
      id: '$sends',
      sender: 'Fixture',
      text: text,
      time: DateTime(2026),
      isSelf: true,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets('privacy hides room code and rejects a retired copy callback', (
    tester,
  ) async {
    size(tester, const Size(1200, 900));
    final port = RoomPort(), views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    addTearDown(session.dispose);
    await tester.pump();
    final raw = views.last;
    (raw['room'] as Map)['code'] = 'TEST42';
    final view = MenuFeatureView.parse(raw);
    var copies = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copies++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Widget page(bool visible) => app(
      MenuRoomsPanel(view: view, showRoomCode: visible, onAction: (_, _) {}),
    );
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST42'), findsOneWidget);
    final oldCopy = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '复制房间码'))
        .onPressed!;
    await tester.pumpWidget(page(false));
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST42'), findsNothing);
    expect(find.text('复制房间码'), findsNothing);
    oldCopy();
    await tester.pump();
    expect(copies, 0);
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制房间码'));
    await tester.pump();
      expect(copies, 1);
      session.dispose();
  });
  for (final memberFallback in [false, true]) {
    test('own room message avatar, member fallback=$memberFallback', () async {
      const avatar =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';
      final port = RoomPort();
      if (memberFallback) port.selfAvatar = avatar;
      port.roomChat.messages = [
        RoomChatMessage(
          sequence: 1,
          id: 'fixture',
          sender: 'Self',
          text: 'hello',
          time: DateTime(2026),
          isSelf: true,
          avatar: memberFallback ? null : avatar,
        ),
      ];
      final views = <Map<String, Object?>>[];
      final ready = Completer<void>();
      final session = MenuRoomsSession(port, (v) {
        views.add(v);
        if (v['state'] == 'ready' && !ready.isCompleted) ready.complete();
      }, chatOnly: true);
      addTearDown(session.dispose);
      session.show(true);
      await ready.future.timeout(const Duration(seconds: 5));
      expect(
        MenuFeatureView.parse(views.last).rows.single.avatar,
        startsWith('data:image/png;base64,'),
      );
    });
  }
  testWidgets(
    'room projection is client-shaped and strips authority; account invalidation clears immediately',
    (tester) async {
      final port = RoomPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      await tester.pump();
      var view = MenuFeatureView.parse(views.last);
      expect(view.room?.members, isNotEmpty);
      expect(jsonEncode(views.last), isNot(contains('example-host')));
      expect(
        view.room!.members.every(
          (member) => member.userRef == null && member.removalToken == null,
        ),
        isTrue,
      );
      session.act(view.buttons.firstWhere((b) => b.label == '聊天').key, '');
      expect(MenuFeatureView.parse(views.last).room, isNotNull);
      await tester.pump();
      view = MenuFeatureView.parse(views.last);
      expect(view.room!.tab, 'chat');
      final send = view.buttons.firstWhere((b) => b.label == '发送消息');
      expect(send.limit, 300);
      session.act(send.key, 'x' * 301);
      await tester.pump();
      expect(port.roomChat.sends, 0);
      port.changes.add(null);
      expect(MenuFeatureView.parse(views.last).room, isNull);
      await tester.pump();
      session.dispose();
    },
  );
  testWidgets(
    'room members reuse localized client fields and retain header while scrolling',
    (tester) async {
      final port = RoomPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      await tester.pump();
      final raw = views.last;
      final room = raw['room'] as Map;
      room['members'] = [
        for (var i = 0; i < 10; i++)
          menuRoomMember(
            RoomMember(
              callsign: '远航者 $i',
              gameId: 'Pilot_$i',
              isHost: i == 0,
              presence: '游戏中',
              presenceKey: 'presence.inGame',
              location: 'Unknown',
              ship: 'F8C Lightning',
              shard: '',
              serverRegion: 'US',
              shipLabels: const {'zhHans': 'F8C 闪电'},
              arrivalPendingConfirmation: true,
              arrivalTargetCode: 'RR_P3_L1',
              arrivalTargetLabels: const {'zhHans': '星光服务站'},
            ),
            null,
          ),
      ];
      room['capacity'] = 12;
      room['memberCount'] = 10;
      for (final width in [1200.0, 390.0]) {
        size(tester, Size(width, 650));
        await tester.pumpWidget(
          app(
            MenuRoomsPanel(
              view: MenuFeatureView.parse(raw),
              onAction: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RoomMemberBanner), findsWidgets);
        expect(find.text('F8C 闪电'), findsWidgets);
        expect(find.textContaining('星光服务站'), findsWidgets);
        final title = find.text(MenuFeatureView.parse(raw).title);
        final rect = tester.getRect(title);
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(tester.getRect(title), rect);
        expect(tester.takeException(), isNull);
      }
      session.dispose();
    },
  );
  testWidgets(
    'embedded room composer enforces 300 and preserves draft during silent reads',
    (tester) async {
      final port = RoomPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      addTearDown(session.dispose);
      await tester.pump();
      var view = MenuFeatureView.parse(views.last);
      session.act(view.buttons.firstWhere((b) => b.label == '聊天').key, '');
      await tester.pump();
      size(tester, const Size(900, 700));
      Widget page() => app(
        MenuRoomsPanel(
          view: MenuFeatureView.parse(views.last),
          active: true,
          onAction: session.act,
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('menu-channel-draft'));
      expect(tester.widget<TextField>(field).maxLength, 300);
      await tester.enterText(field, 'draft');
      final refresh = session.refresh(silent: true);
      await tester.pump();
      await refresh;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'draft');
      expect(tester.takeException(), isNull);
      session.dispose();
    },
  );
}
