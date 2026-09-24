import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/app/localization/party_rooms_strings.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart';

void main() {
  testWidgets(
    'wide directory keeps filters visible and preserves them when resized',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final composition = AppComposition.forShellReview(
        windowChrome: InMemoryWindowChrome(),
      );
      await tester.pumpWidget(StarBridgeApp(composition: composition));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('/rooms')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('rooms-persistent-filter'));
      expect(panel, findsOneWidget);
      expect(find.byKey(const Key('rooms-tag-filter')), findsNothing);
      final branch = find
          .descendant(of: panel, matching: find.byType(ExpansionTile))
          .first;
      await tester.tap(branch);
      await tester.pumpAndSettle();
      final choice = find
          .descendant(of: panel, matching: find.byType(CheckboxListTile))
          .first;
      final choiceKey = tester.widget<CheckboxListTile>(choice).key!;
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byKey(choiceKey)).value,
        isTrue,
      );
      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(find.byKey(const Key('rooms-tag-filter')), findsOneWidget);
      expect(find.text('筛选标签 · 1'), findsOneWidget);
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      await tester.tap(
        find.descendant(of: panel, matching: find.byType(ExpansionTile)).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byKey(choiceKey)).value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('example states are isolated and current-room scene contains no other rooms', () async {
    final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
    await module.refresh();
    expect(module.previewScene, 'directory');
    expect(module.directory!.rooms, hasLength(3));
    await module.selectPreviewScene('current');
    expect(module.directory!.rooms, hasLength(1));
    expect(module.directory!.currentRoomId, 'example-cargo');
    await module.selectPreviewScene('empty');
    expect(module.directory!.rooms, isEmpty);
    await module.selectPreviewScene('error');
    expect(module.state, RoomReadState.unavailable);
    expect(module.directory, isNull);
    await module.selectPreviewScene('directory');
    expect(module.directory!.rooms, hasLength(3));
    module.dispose();
    final normal = PartyRoomsModule(UnavailablePartyRoomsPort());
    expect(normal.previewScene, isNull);
    await normal.selectPreviewScene('current');
    expect(normal.directory, isNull);
    normal.dispose();
  });
  testWidgets(
    'example composition previews room list, membership, empty and failure',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final composition = AppComposition.forShellReview(
        windowChrome: InMemoryWindowChrome(),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('example-room-capture'),
          child: StarBridgeApp(composition: composition),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('/rooms')));
      await tester.pumpAndSettle();
      expect(find.text('示例数据 · 不影响真实房间'), findsOneWidget);
      expect(find.byKey(const Key('rooms-directory')), findsOneWidget);
      expect(find.text('队长游戏版本'), findsWidgets);
      expect(find.text('LIVE'), findsWidgets);
      expect(find.text('EPTU'), findsOneWidget);
      expect(find.textContaining('pub_use1b_'), findsNothing);
      if (const bool.fromEnvironment('ROOM_REVIEW_PNG')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('example-room-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/room-example-review.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      for (final state in ['current', 'host', 'empty', 'error', 'directory']) {
        final labels = {
          'current': '已在房间',
          'host': '房主管理',
          'empty': '暂无房间',
          'error': '读取失败',
          'directory': '房间列表',
        };
        await tester.tap(
          find.byKey(
            ValueKey('rooms-example-${composition.partyRooms.previewScene}'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(labels[state]!).last);
        await tester.pumpAndSettle();
        expect(composition.partyRooms.previewScene, state);
        expect(
          find.byKey(const Key('rooms-directory')),
          state == 'directory' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        if (state == 'host' && const bool.fromEnvironment('ROOM_REVIEW_PNG')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('example-room-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/room-host-review.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  const render = bool.fromEnvironment('ROOM_REVIEW_PNG');
  setUpAll(() async {
    if (!render) return;
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  test('real projection preserves handle and explicit empty membership', () {
    final value = parseRoomDirectory(wire());
    expect(value.currentRoomId, isNull);
    expect(value.rooms.first.members.single.displayName, '测试呼号 (Citizen_CN)');
    expect(value.rooms.first.tags.single.text, '新手友好');
    expect(value.rooms.first.leaderServerRegion, 'US');
    expect(parseRoomDirectory(wire(rooms: [])).rooms, isEmpty);
    final coded = room('a')..['roomCode'] = 'TESTCODE';
    expect(
      parseRoomDirectory(wire(rooms: [coded])).rooms.single.roomCode,
      isEmpty,
    );
    expect(
      parseRoomDirectory(wire(current: 'a', rooms: [coded]))
          .rooms
          .single
          .roomCode,
      'TESTCODE',
    );
  });
  test('older projections omit tags and leader region without guessing', () {
    final old = room('a')
      ..remove('tags')
      ..remove('leaderServerRegion')
      ..remove('leaderGameVersion');
    final result = parseRoomDirectory(wire(rooms: [old]));
    expect(result.rooms.single.tags, isEmpty);
    expect(result.rooms.single.leaderServerRegion, isEmpty);
    expect(result.rooms.single.leaderGameVersion, isEmpty);
    expect(result.rooms.single.members.single.avatarData, isNull);
  });
  test(
    'malformed, duplicate, oversized and contradictory projections fail closed',
    () {
      for (final data in <Map<String, Object?>>[
        {},
        {...wire(), 'schemaVersion': 2},
        {...wire(), 'rooms': null},
        {...wire(), 'currentRoomId': 'missing'},
        wire(rooms: [room('a'), room('a')]),
        wire(
          rooms: [
            {...room('a'), 'capacity': 64},
          ],
        ),
        wire(
          rooms: [
            {...room('a'), 'title': ''},
          ],
        ),
        {
          ...wire(),
          'currentRoomId': 'a',
          'rooms': [room('a'), room('b')],
        },
      ]) {
        expect(() => parseRoomDirectory(data), throwsA(anything));
      }
    },
  );
  test(
    'refresh retains stable selection and falls back only when removed',
    () async {
      final port = TestRoomsPort();
      final module = PartyRoomsModule(port);
      await module.refresh();
      module.select('b');
      port.result = ready(wire(rooms: [room('b'), room('a')]));
      await module.refresh();
      expect(module.selectedRoomId, 'b');
      port.result = ready(wire(rooms: [room('a')]));
      await module.refresh();
      expect(module.selectedRoomId, 'a');
      module.dispose();
    },
  );
  test('authoritative current room blocks selecting another room', () async {
    final port = TestRoomsPort()
      ..result = ready(wire(current: 'a', rooms: [room('a')]));
    final module = PartyRoomsModule(port);
    await module.refresh();
    module.select('b');
    expect(module.selectedRoomId, 'a');
    port.result = ready(wire(rooms: []));
    await module.refresh();
    expect(module.directory!.currentRoomId, isNull);
    expect(module.selectedRoom, isNull);
    module.dispose();
  });
  test(
    'errors and signed out never masquerade as an empty directory',
    () async {
      final port = TestRoomsPort();
      final module = PartyRoomsModule(port);
      await module.refresh();
      for (final state in [
        RoomReadState.unavailable,
        RoomReadState.signedOut,
      ]) {
        port.result = RoomReadResult(state);
        await module.refresh();
        expect(module.state, state);
        expect(module.directory, isNull);
        expect(module.selectedRoomId, isNull);
      }
      module.dispose();
    },
  );
  test(
    'account invalidation clears immediately and rejects late read',
    () async {
      final port = TestRoomsPort();
      final module = PartyRoomsModule(port);
      await module.refresh();
      final pending = Completer<RoomReadResult>();
      port.pending = pending;
      final read = module.refresh();
      port.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(module.directory, isNull);
      pending.complete(ready(wire()));
      await read;
      expect(module.directory, isNull);
      module.dispose();
    },
  );
  test('leaving cancels publication and reentry reads fresh state', () async {
    final port = TestRoomsPort();
    final module = PartyRoomsModule(port);
    final pending = Completer<RoomReadResult>();
    port.pending = pending;
    module.enter();
    module.leave();
    pending.complete(ready(wire()));
    await Future<void>.delayed(Duration.zero);
    expect(module.directory, isNull);
    port.pending = null;
    module.enter();
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, 2);
    expect(module.directory, isNotNull);
    module.dispose();
  });
  test('dispose ignores late completion and closes port', () async {
    final port = TestRoomsPort()..pending = Completer<RoomReadResult>();
    final module = PartyRoomsModule(port);
    final read = module.refresh();
    module.dispose();
    port.pending!.complete(ready(wire()));
    await read;
    expect(port.closed, isTrue);
    expect(module.directory, isNull);
  });
  test('all supported languages cover the same room keys', () {
    expect(
      traditionalPartyRoomsStrings.keys.toSet(),
      simplifiedPartyRoomsStrings.keys.toSet(),
    );
    expect(
      englishPartyRoomsStrings.keys.toSet(),
      simplifiedPartyRoomsStrings.keys.toSet(),
    );
  });
  for (final width in [1000.0, 1280.0, 1500.0]) {
    testWidgets('room directory and real details fit at width $width', (
      tester,
    ) async {
      final port = TestRoomsPort();
      final composition = await pumpRooms(
        tester,
        port,
        Size(width, width == 1280 ? 720 : 900),
      );
      expect(find.byKey(const Key('rooms-directory')), findsOneWidget);
      final firstCard = find.byKey(const Key('room-a'));
      for (final value in [
        '房主 · 测试呼号 (Citizen_CN)',
        '队长当前服务器',
        '美服',
        '队长游戏版本',
        'LIVE',
      ]) {
        expect(
          find.descendant(of: firstCard, matching: find.text(value)),
          findsOneWidget,
        );
      }
      expect(find.text('成员预览'), findsNothing);
      expect(find.byKey(const Key('room-tags')), findsWidgets);
      expect(find.text('EPTU'), findsOneWidget);
      expect(find.text('欧服'), findsOneWidget);
      for (final hidden in [
        '应用在线',
        '奥里森',
        'C2 Hercules',
        'pub_use1b_00000000_001',
        '服务端解散时间',
        '上次读取',
        '状态',
        '位置',
        '舰船',
        '服务器',
      ]) {
        expect(
          find.text(hidden),
          findsNothing,
          reason: 'Discovery must not render member telemetry or technical timestamps',
        );
      }
      await tester.ensureVisible(find.byKey(const Key('room-b')));
      await tester.tap(find.byKey(const Key('room-b')));
      await tester.pumpAndSettle();
      expect(composition.partyRooms.selectedRoomId, 'b');
      await tester.tap(find.text('刷新房间'));
      await tester.pumpAndSettle();
      expect(composition.partyRooms.selectedRoomId, 'b');
      expect(tester.takeException(), isNull);
      if (render) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('room-review-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/room-review-$width.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('joined room has no directory and recovers into discovery', (
    tester,
  ) async {
    final port = TestRoomsPort()
      ..result = ready(wire(current: 'a', rooms: [room('a')]));
    await pumpRooms(tester, port, const Size(1280, 800));
    expect(find.byKey(const Key('rooms-directory')), findsNothing);
    expect(find.text('当前房间'), findsOneWidget);
    expect(find.byKey(const Key('room-member-preview')), findsNothing);
    for (final value in ['应用在线', '奥里森', 'C2 Hercules', '美服']) {
      expect(
        find.text(value),
        findsOneWidget,
        reason: 'Joined-room details remain available',
      );
    }
    expect(find.textContaining('pub_use1b_'), findsNothing);
    for (final entry in {
      'EU': '欧服',
      'ASIA': '亚服',
      'AU': '澳服',
      '': '暂无可见信息',
      'pub_use1b_00000000_001': '暂无可见信息',
    }.entries) {
      final data = room('a');
      ((data['members'] as List).single
              as Map<String, Object?>)['serverRegion'] =
          entry.key;
      port.result = ready(wire(current: 'a', rooms: [data]));
      await tester.tap(find.text('刷新房间'));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('pub_use1b_'), findsNothing);
    }
    port.result = ready(wire(rooms: []));
    await tester.tap(find.text('刷新房间'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rooms-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('permission failure is visible rather than no rooms', (
    tester,
  ) async {
    final port = TestRoomsPort()
      ..result = const RoomReadResult(
        RoomReadState.unavailable,
        failure: 'forbidden',
      );
    await pumpRooms(tester, port, const Size(1280, 800));
    expect(find.textContaining('没有读取房间的权限'), findsOneWidget);
    expect(find.byKey(const Key('rooms-empty')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'member banners use actual avatars and keep the entire roster reachable',
    (tester) async {
      const avatar =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      final data = room('a');
      final host = (data['members'] as List).single as Map<String, Object?>;
      data['capacity'] = 16;
      data['members'] = [
        {...host, 'avatarImageData': avatar},
        for (var i = 1; i < 16; i++)
          {
            ...host,
            'callsign': '成员$i',
            'gameId': 'Citizen_$i',
            'isHost': false,
            'avatarImageData': 'https://not-fetched.test/avatar.png',
          },
      ];
      final port = TestRoomsPort()
        ..result = ready(wire(current: 'a', rooms: [data]));
      await pumpRooms(tester, port, const Size(1280, 900));
      expect(find.byKey(const Key('member-banner-Citizen_CN')), findsOneWidget);
      final hostAvatar = find.descendant(
        of: find.byKey(const Key('member-banner-Citizen_CN')),
        matching: find.byType(RoomAvatar),
      );
      expect(
        find.descendant(of: hostAvatar, matching: find.byType(Image)),
        findsOneWidget,
      );
      await tester.tap(find.text('房间资料'));
      await tester.pumpAndSettle();
      expect(find.text('加入方式'), findsOneWidget);
      await tester.tap(find.text('收起资料'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('member-banner-Citizen_15')),
        250,
        scrollable: find.descendant(
          of: find.byKey(const Key('room-details-a')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('member-banner-Citizen_15')).hitTestable(),
        findsOneWidget,
      );
      final last = find.byKey(const Key('member-banner-Citizen_15'));
      expect(
        find.descendant(of: last, matching: find.byType(Image)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<AppComposition> pumpRooms(
  WidgetTester tester,
  TestRoomsPort port,
  Size size,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forTest(
    windowChrome: InMemoryWindowChrome(),
    partyRoomsPort: port,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('room-review-capture'),
      child: StarBridgeApp(composition: composition),
    ),
  );
  await tester.pumpAndSettle();
  expect(port.reads, 1, reason: 'Mounted shell establishes the room session');
  await tester.tap(find.byKey(const ValueKey('/rooms')));
  await tester.pumpAndSettle();
  return composition;
}

class TestRoomsPort implements PartyRoomsPort {
  final events = StreamController<void>.broadcast();
  RoomReadResult result = ready(wire());
  Completer<RoomReadResult>? pending;
  int reads = 0;
  bool closed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<RoomReadResult> read() async {
    reads++;
    return pending?.future ?? result;
  }

  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

RoomReadResult ready(Map<String, Object?> value) =>
    RoomReadResult(RoomReadState.ready, directory: parseRoomDirectory(value));
Map<String, Object?> wire({
  String? current,
  List<Map<String, Object?>>? rooms,
}) => {
  'schemaVersion': 1,
  'currentRoomId': current,
  'serverTime': '2026-09-05T12:00:00Z',
  'rooms': rooms ?? [room('a'), room('b')],
};
Map<String, Object?> room(String id) => {
  'roomId': id,
  'title': '测试房间 $id',
  'goal': '测试目标',
  'capacity': 4,
  'isPublic': true,
  'eligibility': 'everyone',
  'admissionMode': 'approval',
  'passwordRequired': false,
  'voiceRequirement': 'recommended',
  'language': id == 'b' ? 'en' : 'zh',
  'expiresAt': '2026-09-06T12:00:00Z',
  'recruitmentClosesAt': null,
  'viewerIsHost': false,
  'leaderServerRegion': id == 'b' ? 'EU' : 'US',
  'leaderGameVersion': id == 'b' ? 'EPTU' : 'LIVE',
  'tags': [
    {'id': 'experience_beginner_friendly', 'text': '新手友好', 'isGameplay': false},
  ],
  'members': [
    {
      'callsign': '测试呼号',
      'gameId': 'Citizen_CN',
      'isHost': true,
      'presenceText': '应用在线',
      'locationText': '奥里森',
      'shipText': 'C2 Hercules',
      'shardText': 'pub_use1b_00000000_001',
      'serverRegion': 'US',
    },
  ],
};
