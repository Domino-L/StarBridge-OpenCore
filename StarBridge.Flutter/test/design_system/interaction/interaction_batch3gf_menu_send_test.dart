import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_composer.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../app/menu_overlay/menu_comms_channels_test.dart' show channel;
import '../../app/menu_overlay/menu_rooms_panel_test.dart' show RoomPort, Chat;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3gb_logs_presets_test.dart' show actTarget;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;

const _label = '正在确认发送结果，请勿重复提交。';
final _review = visualOutputDir(
  'interaction_motion_batch3gf_20261017',
  legacySubdirectory: 'review',
);
final _marker = find.byKey(const ValueKey('menu-channel-send-activity'));
final _input = find.byKey(const ValueKey('menu-channel-draft'));

class _Probe {
  _Probe(this.suite, {this.room = false, this.organization = false});
  final InteractionSuite suite;
  final bool room, organization;
  final capture = GlobalKey();
  final actions = <(String, String)>[];
  void Function(String, String)? dispatch;
  bool reduce = false, active = true;
  double scale = 1;
  late StateSetter update;
  var raw = channel();
  SemanticsHandle? semantics;

  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        return scopedApp(
          Theme(
            data: buildMenuOverlayTheme(const Locale('zh')),
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: MenuChannelPanel(
                  view: MenuFeatureView.parse(raw),
                  active: active,
                  embeddedRoom: room,
                  embeddedOrganization: organization,
                  onAction: (key, text) {
                    actions.add((key, text));
                    dispatch?.call(key, text);
                  },
                ),
              ),
            ),
          ),
          suite,
          reduce: reduce,
        );
      },
    ),
  );

  Future<void> mount(WidgetTester t) async {
    (raw['chat'] as Map)['receipts'] = <String, String>{};
    semantics = t.ensureSemantics();
    size(t, const Size(1000, 900));
    await t.pumpWidget(app());
    await frames(t);
  }

  Future<void> send(WidgetTester t, String source) async {
    await t.enterText(_input, '准备出发');
    await t.pump();
    if (source == 'enter') {
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
    } else {
      final button = find
          .ancestor(
            of: find.byKey(const ValueKey('menu-channel-send')),
            matching: find.byType(StarBridgeActionButton),
          )
          .first;
      await actTarget(t, button, source);
    }
    await frames(t);
  }

  void reply({String status = 'sent', int revision = 1, String scope = 's1'}) {
    update(() {
      raw = channel(status: status, revision: revision, scope: scope);
      (raw['chat'] as Map)['receipts'] = <String, String>{};
    });
  }

  Future<void> clean(WidgetTester t) async {
    semantics?.dispose();
    semantics = null;
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  }
}

class _HeldChat extends Chat {
  final pending = Completer<RoomChatMessage>();
  final requests = <(String, String)>[];
  @override
  Future<RoomChatMessage> send(String roomId, String text) {
    requests.add((roomId, text));
    return pending.future;
  }
}

class _RoomPort extends RoomPort {
  @override
  // ignore: overridden_fields
  final _HeldChat roomChat = _HeldChat();
}

void waitMarker(WidgetTester t, {required bool animated}) {
  expect(_marker, findsOneWidget);
  expect(find.text(_label), findsOneWidget);
  expect(
    find.descendant(of: _marker, matching: find.byType(SocialReadActivity)),
    findsOneWidget,
  );
  final busy = find.descendant(
    of: _marker,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
  final progress = find.descendant(
    of: _marker,
    matching: find.byType(LinearProgressIndicator),
  );
  expect(t.widget<LinearProgressIndicator>(progress).minHeight, 2);
}

// ignore: library_private_types_in_public_api
Future<List<int>> pixels(WidgetTester t, _Probe p, {bool save = false}) async =>
    (await t.runAsync(() async {
      final boundary =
          p.capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        if (save) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(_review).create(recursive: true);
          await File('$_review/${p.suite.name}-send.png')
              .writeAsBytes(png!.buffer.asUint8List());
        }
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final rect = t.getRect(_marker);
        final raw = bytes!.buffer.asUint8List();
        return <int>[
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
            ...raw.sublist(
              (y * image.width + rect.left.ceil()) * 4,
              (y * image.width + rect.right.floor()) * 4,
            ),
        ];
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  setUpAll(loadFonts);
  testWidgets('3gf admitted mouse send has wait marker', (t) async {
    final p = _Probe(InteractionSuite.rail);
    await p.mount(t);
    expect(_marker, findsNothing);
    await p.send(t, 'pointer');
    waitMarker(t, animated: true);
    expect(p.actions, [('a1', '准备出发')]);
    await p.clean(t);
  });
  testWidgets('3gf actual room Enter has static wait marker', (t) async {
    final p = _Probe(InteractionSuite.scan, room: true);
    await p.mount(t);
    await p.send(t, 'enter');
    waitMarker(t, animated: false);
    expect(p.actions, [('a1', '准备出发')]);
    await p.clean(t);
  });

  for (final source in ['pointer', 'keyboard', 'reader']) {
    for (final fail in [false, true]) {
      testWidgets('3gf real room owner $source failure=$fail handoff', (
        t,
      ) async {
        final p = _Probe(InteractionSuite.scan, room: true);
        final port = _RoomPort();
        var mounted = false;
        final session = MenuRoomsSession(port, (raw) {
          if (mounted) {
            p.update(() => p.raw = raw);
          } else {
            p.raw = raw;
          }
        }, chatOnly: true)..show(true);
        p.dispatch = session.act;
        await t.pump();
        expect(MenuFeatureView.parse(p.raw).chat!.outbox, isNull);
        await p.mount(t);
        mounted = true;
        await p.send(t, source);
        waitMarker(t, animated: source == 'pointer');
        expect(port.roomChat.requests.single.$2, '准备出发');
        if (fail) {
          port.roomChat.pending.completeError(StateError('synthetic failure'));
        } else {
          port.roomChat.pending.complete(
            RoomChatMessage(
              sequence: 1,
              id: 'synthetic',
              sender: 'Fixture',
              text: '准备出发',
              time: DateTime.utc(2026),
              isSelf: true,
            ),
          );
        }
        await frames(t);
        expect(_marker, findsNothing);
        expect(
          t.widget<TextField>(_input).controller!.text,
          fail ? '准备出发' : '',
        );
        expect(
          MenuFeatureView.parse(p.raw).chat!.status,
          fail ? 'unknown' : 'sent',
        );
        expect(port.roomChat.requests, hasLength(1));
        mounted = false;
        session.dispose();
        await p.clean(t);
        await t.pump(const Duration(seconds: 13));
      });
    }
  }

  for (final suite in InteractionSuite.values) {
    testWidgets('3gf $suite stale callback cannot replace pending source', (
      t,
    ) async {
      final p = _Probe(suite, room: true);
      await p.mount(t);
      await t.enterText(_input, '准备出发');
      await t.pump();
      final stale = t
          .widget<RoomChatComposer>(find.byType(RoomChatComposer))
          .onSend!;
      await p.send(t, 'pointer');
      stale();
      await frames(t);
      waitMarker(t, animated: true);
      expect(p.actions, [('a1', '准备出发')]);
      await p.clean(t);
    });
    testWidgets('3gf $suite outbox handoff never duplicates legacy marker', (
      t,
    ) async {
      final p = _Probe(suite, organization: true);
      (p.raw['chat'] as Map)['outboxVersion'] = 1;
      (p.raw['chat'] as Map)['localMessages'] = <Map<String, Object?>>[];
      await p.mount(t);
      expect(MenuFeatureView.parse(p.raw).chat!.outbox, isNotNull);
      await p.send(t, 'pointer');
      expect(_marker, findsNothing);
      expect(find.text(_label), findsNothing);
      expect(p.actions, [('a1', '准备出发')]);
      await p.clean(t);
    });
    testWidgets('3gf $suite hidden pending keeps guard without animation', (
      t,
    ) async {
      final p = _Probe(suite, room: true);
      await p.mount(t);
      await p.send(t, 'pointer');
      p.update(() => p.active = false);
      await frames(t);
      waitMarker(t, animated: false);
      final a = await pixels(t, p);
      await frames(t, 20);
      expect(changed(a, await pixels(t, p)), 0);
      expect(p.actions, [('a1', '准备出发')]);
      expect(t.widget<TextField>(_input).controller!.text, '准备出发');
      p.update(() => p.active = true);
      await frames(t);
      waitMarker(t, animated: true);
      expect(p.actions, [('a1', '准备出发')]);
      await p.clean(t);
    });
    testWidgets('3gf $suite initial reduce preserves static wait', (t) async {
      final p = _Probe(suite)..reduce = true;
      await p.mount(t);
      await p.send(t, 'pointer');
      waitMarker(t, animated: false);
      p.reply();
      await frames(t);
      expect(_marker, findsNothing);
      await p.clean(t);
    });
    for (final source in ['pointer', 'keyboard', 'reader', 'enter']) {
      testWidgets('3gf $suite $source admitted source stays through busy', (
        t,
      ) async {
        final p = _Probe(suite, room: true);
        await p.mount(t);
        await p.send(t, source);
        waitMarker(t, animated: source == 'pointer');
        p.update(() => p.raw['busy'] = true);
        await frames(t);
        waitMarker(t, animated: source == 'pointer');
        expect(p.actions, [('a1', '准备出发')]);
        expect(t.widget<TextField>(_input).readOnly, isTrue);
        final labelNode = t.getSemantics(find.text(_label));
        expect(labelNode.getSemanticsData().label, _label);
        expect(labelNode.getSemanticsData().value, isEmpty);
        await p.clean(t);
      });
    }
    for (final failure in ['rejected', 'unknown']) {
      testWidgets('3gf $suite $failure retains draft and original retry gate', (
        t,
      ) async {
        final p = _Probe(suite);
        await p.mount(t);
        await p.send(t, 'pointer');
        p.reply(status: failure, revision: 0);
        await frames(t);
        expect(_marker, findsNothing);
        expect(t.widget<TextField>(_input).controller!.text, '准备出发');
        if (failure == 'rejected') {
          await p.send(t, 'keyboard');
          waitMarker(t, animated: false);
          expect(p.actions, [('a1', '准备出发'), ('a1', '准备出发')]);
          p.reply();
          await frames(t);
          expect(_marker, findsNothing);
          expect(t.widget<TextField>(_input).controller!.text, isEmpty);
        } else {
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          expect(p.actions, [('a1', '准备出发')]);
        }
        await p.clean(t);
      });
    }
    testWidgets('3gf $suite scope change retires wait and old draft', (
      t,
    ) async {
      final p = _Probe(suite);
      await p.mount(t);
      await p.send(t, 'pointer');
      p.reply(scope: 's2', status: 'idle', revision: 0);
      await frames(t);
      expect(_marker, findsNothing);
      expect(t.widget<TextField>(_input).controller!.text, isEmpty);
      expect(p.actions, [('a1', '准备出发')]);
      await p.clean(t);
    });
    testWidgets(
      '3gf $suite unknown busy without local submit has no send wait',
      (t) async {
        final p = _Probe(suite)..raw['busy'] = true;
        await p.mount(t);
        expect(_marker, findsNothing);
        expect(p.actions, isEmpty);
        await p.clean(t);
      },
    );
    testWidgets('3gf $suite review active wait and live reduce', (t) async {
      final p = _Probe(suite, room: true)..scale = 1.5;
      await p.mount(t);
      await p.send(t, 'pointer');
      waitMarker(t, animated: true);
      final rect = t.getRect(_marker);
      final a = await pixels(t, p, save: true);
      await frames(t, 13);
      expect(changed(a, await pixels(t, p)), greaterThan(0));
      p.update(() => p.reduce = true);
      await frames(t, 2);
      waitMarker(t, animated: false);
      final b = await pixels(t, p);
      await frames(t, 38);
      expect(changed(b, await pixels(t, p)), 0);
      expect(t.getRect(_marker), rect);
      await p.clean(t);
    });
  }
}
