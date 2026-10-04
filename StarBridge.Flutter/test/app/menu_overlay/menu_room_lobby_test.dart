import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_lobby_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

class LobbySource implements PartyRoomsPort, RoomCommandsPort {
  final source = ExamplePartyRoomsAdapter();
  final changes = StreamController<void>.broadcast(sync: true);
  final calls = <RoomCommand>[];
  bool empty = false, unknown = false;
  @override
  bool get supportsCommands => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<void> close() => changes.close();
  @override
  Future<RoomReadResult> read() async {
    final directory = (await source.read()).directory!;
    return RoomReadResult(
      RoomReadState.ready,
      directory: RoomDirectory(
        rooms: empty ? [] : directory.rooms,
        currentRoomId: null,
        serverTime: directory.serverTime,
        tagOptions: directory.tagOptions,
      ),
    );
  }

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    calls.add(command);
    if (unknown) {
      return const RoomCommandResult('unknown', error: 'outcomeUnknown');
    }
    if (command.operation == RoomOperation.resolve) {
      return RoomCommandResult(
        'resolved',
        preview: (await source.read()).directory!.rooms.first,
      );
    }
    return source.execute(command);
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'empty and populated lobby reuse client creation, search and filtering at wide and narrow sizes',
    (tester) async {
      final source = LobbySource(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(source, views.add)..show(true);
      addTearDown(session.dispose);
      await tester.pump();
      final boundary = GlobalKey();
      for (final width in [1200.0, 390.0]) {
        size(tester, Size(width, 850));
        await tester.pumpWidget(
          app(
            RepaintBoundary(
              key: boundary,
              child: MenuRoomsPanel(
                view: MenuFeatureView.parse(views.last),
                onAction: session.act,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PartyRoomsPage), findsOneWidget);
        expect(find.text('创建房间'), findsOneWidget);
        expect(find.byKey(const Key('rooms-tag-search')), findsOneWidget);
        await capture(tester, boundary, 'menu-room-lobby-${width.toInt()}');
        await tester.tap(find.text('创建房间'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('room-create-title')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('room-create-title')),
          'draft room',
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(source.calls, isEmpty);
        expect(tester.takeException(), isNull);
      }
      source.empty = true;
      await session.refresh();
      await tester.pumpWidget(
        app(
          MenuRoomsPanel(
            view: MenuFeatureView.parse(views.last),
            onAction: session.act,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('创建房间'), findsOneWidget);
      expect(find.byKey(const Key('rooms-empty')), findsOneWidget);
      await tester.tap(find.text('创建房间'));
      await tester.pumpAndSettle();
      // Scope disposal must also retire the nested dialog, never leave account UI.
      source.changes.add(null);
      await tester.pumpWidget(
        app(
          MenuRoomsPanel(
            view: MenuFeatureView.parse(views.last),
            onAction: session.act,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('room-create-title')), findsNothing);
      expect(tester.takeException(), isNull);
      session.dispose();
    },
  );

  testWidgets(
    'resolved private preview survives directory refresh; opaque actions round trip without leaking IDs',
    (tester) async {
      final source = LobbySource()..empty = true;
      final views = <Map<String, Object?>>[];
      MenuRoomLobbyPort? proxy;
      final session = MenuRoomsSession(source, (raw) {
        views.add(raw);
        final lobby = MenuFeatureView.parse(raw).lobby;
        if (lobby != null) proxy?.update(lobby);
      })..show(true);
      addTearDown(session.dispose);
      await tester.pump();
      proxy = MenuRoomLobbyPort(
        MenuFeatureView.parse(views.last).lobby!,
        session.act,
      );
      final resolving = proxy.execute(
        RoomCommand(RoomOperation.resolve, {'roomCode': 'fixture'}),
      );
      await tester.pump();
      final result = await resolving;
      expect(result.status, 'resolved');
      expect(result.preview!.id, matches(r'^r[0-9]+$'));
      await session.refresh();
      await tester.pump();
      expect(jsonEncode(views.last), isNot(contains('example-cargo')));
      final joining = proxy.execute(
        RoomCommand(RoomOperation.join, {
          'roomId': result.preview!.id,
          'password': '',
        }),
      );
      await tester.pump();
      expect((await joining).status, 'pending');
      expect(source.calls.last.data['roomId'], 'example-cargo');
      final old = proxy.view.actions[RoomOperation.join]!;
      source.changes.add(null);
      session.act(
        old,
        jsonEncode({
          'request': 'q99',
          'data': {'roomId': result.preview!.id},
        }),
      );
      await tester.pump();
      expect(source.calls.length, 2);
      await proxy.close();
      session.dispose();
    },
  );

  testWidgets('unknown creation locks writes and never retries a mutation', (
    tester,
  ) async {
    final source = LobbySource()..unknown = true;
    final views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(source, views.add)..show(true);
    addTearDown(session.dispose);
    await tester.pump();
    final key = MenuFeatureView.parse(views.last)
        .lobby!
        .actions[RoomOperation.create]!;
    final data = jsonEncode({
      'request': 'q1',
      'data': {'title': 'fixture'},
    });
    session.act(key, data);
    await tester.pump();
    final view = MenuFeatureView.parse(views.last);
    expect(view.lobby!.actions, isEmpty);
    expect(view.lobby!.reply!['status'], 'unknown');
    session.act(key, data);
    await tester.pump();
    expect(source.calls.length, 1);
    session.dispose();
  });
}
