import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_preset_port.dart';

import 'menu_room_management_test.dart' show RoomPort;
import 'menu_rooms_panel_test.dart' show Chat;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;

class PresetChat extends Chat implements RoomPresetPort {
  @override
  bool presetsAvailable = true;
  bool fail = false;
  int catalogs = 0, exports = 0, imports = 0;
  String? sentRoom, exportedId;
  int? exportedRevision;
  Map<String, Object?>? sentAttachment;
  Completer<Map<String, Object?>>? heldExport;
  static const attachment = {
    'kind': 'overlay_preset',
    'title': '测试预设',
    'overlayPresetPackage': 'private-package-not-for-renderer',
  };
  @override
  Future<RoomPresetCatalog> readPresets() async {
    catalogs++;
    return const RoomPresetCatalog(99123, [
      RoomPresetChoice('private-preset-id', '测试预设'),
    ]);
  }

  @override
  Future<Map<String, Object?>> exportPreset(String id, int revision) async {
    exports++;
    exportedId = id;
    exportedRevision = revision;
    return heldExport == null ? attachment : await heldExport!.future;
  }

  @override
  Future<String> importPreset(String package, int revision) async {
    imports++;
    return '';
  }

  @override
  Future<RoomChatMessage> sendPreset(
    String roomId,
    String text,
    Map<String, Object?> attachment,
  ) async {
    sentRoom = roomId;
    sentAttachment = attachment;
    if (fail) {
      sends++;
      throw const RoomChatFailure('outcomeUnknown');
    }
    return send(roomId, text);
  }
}

class PresetPort extends RoomPort implements RoomChatProvider {
  @override
  final PresetChat roomChat = PresetChat();
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'picker projects only names and opaque choices; prepare clear and send once',
    (tester) async {
      final port = PresetPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      MenuFeatureView view() => MenuFeatureView.parse(views.last);
      final open = view().chat!.preset!.open!;
      session.act(open, '');
      await tester.pump();
      expect(port.roomChat.catalogs, 1);
      expect(port.roomChat.sends, 0);
      final select = view().chat!.preset!.choices.single.id;
      // Payload cannot substitute another package, preset id or path.
      session.act(select, '{"package":"evil","path":"elsewhere"}');
      await tester.pump();
      expect(port.roomChat.exportedId, 'private-preset-id');
      expect(port.roomChat.exportedRevision, 99123);
      expect(view().chat!.preset!.draftName, '测试预设');
      expect(port.roomChat.sends, 0);
      final oldClear = view().chat!.preset!.clear!;
      session.act(oldClear, '');
      await tester.pump();
      expect(view().chat!.preset!.draftName, isNull);
      session.act(view().chat!.preset!.choices.single.id, '');
      await tester.pump();
      session.act(oldClear, '');
      await tester.pump();
      expect(view().chat!.preset!.draftName, '测试预设');
      final send = view().buttons.singleWhere((b) => b.label == '发送消息');
      session.act(send.key, '');
      session.act(send.key, '');
      await tester.pump();
      expect(port.roomChat.sends, 1);
      expect(port.roomChat.sentRoom, 'private-room');
      expect(port.roomChat.sentAttachment, PresetChat.attachment);
      expect(view().chat!.preset!.draftName, isNull);
      for (final secret in [
        'private-room',
        'private-preset-id',
        '99123',
        'private-package-not-for-renderer',
        'overlayPresetPackage',
      ]) {
        expect(jsonEncode(views), isNot(contains(secret)));
      }
      session.dispose();
    },
  );

  for (final invalidation in ['left', 'capability', 'account']) {
    testWidgets('preset draft and actions retire after $invalidation', (
      tester,
    ) async {
      final port = PresetPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      MenuFeatureView view() => MenuFeatureView.parse(views.last);
      session.act(view().chat!.preset!.open!, '');
      await tester.pump();
      final choice = view().chat!.preset!.choices.single.id;
      if (invalidation == 'left') port.joined = false;
      if (invalidation == 'capability') port.roomChat.presetsAvailable = false;
      if (invalidation == 'account') port.changes.add(null);
      session.act(choice, '');
      await tester.pump();
      expect(port.roomChat.exports, 0);
      expect(port.roomChat.sends, 0);
      expect(view().chat?.preset?.draftName, isNull);
      session.dispose();
    });
  }

  testWidgets('late export cannot restore a draft after account invalidation', (
    tester,
  ) async {
    final port = PresetPort(), views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    MenuFeatureView view() => MenuFeatureView.parse(views.last);
    session.act(view().chat!.preset!.open!, '');
    await tester.pump();
    port.roomChat.heldExport = Completer();
    session.act(view().chat!.preset!.choices.single.id, '');
    await tester.pump();
    expect(port.roomChat.exports, 1);
    port.changes.add(null);
    await tester.pump();
    port.roomChat.heldExport!.complete(PresetChat.attachment);
    await tester.pump();
    expect(view().chat?.preset?.draftName, isNull);
    expect(port.roomChat.sends, 0);
    session.dispose();
  });

  for (final invalidation in ['left', 'capability', 'account']) {
    testWidgets('prepared attachment is cleared after $invalidation', (
      tester,
    ) async {
      final port = PresetPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      MenuFeatureView view() => MenuFeatureView.parse(views.last);
      session.act(view().chat!.preset!.open!, '');
      await tester.pump();
      session.act(view().chat!.preset!.choices.single.id, '');
      await tester.pump();
      expect(view().chat!.preset!.draftName, '测试预设');
      if (invalidation == 'left') port.joined = false;
      if (invalidation == 'capability') port.roomChat.presetsAvailable = false;
      if (invalidation == 'account') port.changes.add(null);
      await tester.pump();
      await session.refresh();
      expect(view().chat?.preset?.draftName, isNull);
      expect(port.roomChat.sends, 0);
      session.dispose();
    });
  }

  testWidgets(
    'unknown preset send cannot replay through old or refreshed action',
    (tester) async {
      final port = PresetPort(), views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(port, views.add)..show(true);
      await tester.pump();
      MenuFeatureView view() => MenuFeatureView.parse(views.last);
      session.act(view().chat!.preset!.open!, '');
      await tester.pump();
      session.act(view().chat!.preset!.choices.single.id, '');
      await tester.pump();
      port.roomChat.fail = true;
      final send = view().buttons.singleWhere((b) => b.label == '发送消息');
      session.act(send.key, '');
      await tester.pump();
      expect(view().chat!.status, 'unknown');
      session.act(send.key, '');
      await session.refresh();
      expect(view().buttons.where((b) => b.label == '发送消息'), isEmpty);
      expect(view().chat!.preset!.open, isNull);
      expect(view().chat!.preset!.clear, isNull);
      expect(port.roomChat.sends, 1);
      session.dispose();
    },
  );

  testWidgets(
    'shared picker cancel sends nothing; selection retains text and can clear attachment',
    (tester) async {
      size(tester, const Size(1440, 900));
      final port = PresetPort();
      final frame = ValueNotifier(const MenuFeatureView('loading'));
      final session = MenuRoomsSession(
        port,
        (raw) => frame.value = MenuFeatureView.parse(raw),
      )..show(true);
      await tester.pump();
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<MenuFeatureView>(
            valueListenable: frame,
            builder: (_, view, _) =>
                MenuRoomsPanel(view: view, onAction: session.act, active: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menu-channel-draft')),
        '保留文字',
      );
      await tester.tap(find.byKey(const ValueKey('menu-room-share-preset')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(port.roomChat.exports, 0);
      expect(port.roomChat.sends, 0);
      expect(find.text('保留文字'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-room-share-preset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试预设'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('保留文字'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('menu-room-clear-preset')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('menu-room-clear-preset')));
      await tester.pumpAndSettle();
      expect(frame.value.chat!.preset!.draftName, isNull);
      expect(port.roomChat.sends, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      frame.dispose();
    },
  );
}
