import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;

final class DelayedFeature extends MenuFeatureSession {
  DelayedFeature(super.publish, super.invalidations);
  final reads = <Completer<void>>[];
  final command = Completer<void>();
  int writes = 0;
  @override
  void reset() {}
  @override
  Future<void> closePort() async {}
  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation, pending = Completer<void>();
    reads.add(pending);
    await pending.future;
    if (!current(epoch)) throw StateError('retired');
    return {
      'title': 'fixture',
      'buttons': [
        button('write', (_) async {
          writes++;
          await command.future;
        }),
      ],
    };
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets('timed out and hidden reads cannot mint new action authority', (
    tester,
  ) async {
    final views = <Map<String, Object?>>[],
        invalidations = StreamController<void>.broadcast();
    final feature = DelayedFeature(views.add, invalidations.stream)..show(true);
    await tester.pump(const Duration(seconds: 13));
    expect(views.last['state'], 'unavailable');
    feature.reads.first.complete();
    await tester.pump();
    expect(views.last['state'], 'unavailable');
    feature.act('a1', '');
    expect(feature.writes, 0);
    feature.show(false);
    final count = views.length;
    feature.show(true);
    feature.show(false);
    feature.reads.last.complete();
    await tester.pump();
    expect(views.length, count + 1);
    feature.dispose();
    await invalidations.close();
  });
  testWidgets('in-flight writes stay locked across hide and reopen', (
    tester,
  ) async {
    final views = <Map<String, Object?>>[];
    final feature = DelayedFeature(views.add, const Stream.empty())..show(true);
    feature.reads.single.complete();
    await tester.pump();
    final key =
        ((views.last['buttons'] as List).single as Map)['key'] as String;
    feature.act(key, '');
    expect(feature.writes, 1);
    feature.show(false);
    feature.show(true);
    feature.act(key, '');
    expect(feature.writes, 1);
    expect(feature.reads.length, 1);
    feature.command.complete();
    await tester.pump();
    expect(feature.reads.length, 2);
    feature.show(false);
    feature.reads.last.complete();
    await tester.pump();
    feature.dispose();
  });
  testWidgets('room target stays primary; opening never changes membership', (
    tester,
  ) async {
    final port = ExamplePartyRoomsAdapter(), views = <Map<String, Object?>>[];
    final session = MenuRoomsSession(port, views.add)..show(true);
    await tester.pump();
    var view = MenuFeatureView.parse(views.last);
    expect(view.state, 'ready');
    expect((await port.read()).directory!.currentRoomId, isNull);
    expect(jsonEncode(views.last), isNot(contains('example-cargo')));
    session.act(view.rows.first.buttons.single.key, '');
    await tester.pump();
    view = MenuFeatureView.parse(views.last);
    final join = view.buttons.singleWhere((a) => a.label == '加入房间');
    expect(join.confirm, isNotEmpty);
    session.act('example-cargo', '');
    expect((await port.read()).directory!.currentRoomId, isNull);
    session.act(join.key, '');
    await tester.pump();
    expect((await port.read()).directory!.currentRoomId, isNull);
    expect(MenuFeatureView.parse(views.last).notice, contains('申请已提交'));
    session.dispose();
  });
  test(
    'layout accepts geometry only, never saved targets or invalid numbers',
    () {
      final good = MenuWindowPreferences.defaults.toMap();
      expect(MenuWindowPreferences.parse(good), isNotNull);
      for (final layout in [
        {
          'version': 1,
          'panels': [],
          'open': ['friends'],
        },
        {
          'version': 1,
          'panels': [
            {
              'id': 'p1',
              'bounds': [1, 2, 300, 400],
            },
          ],
          'open': [],
        },
        {
          'version': 1,
          'panels': [
            {
              'id': 'browser',
              'bounds': [1, 2, double.nan, 400],
            },
          ],
          'open': [],
        },
        {
          'version': 1,
          'panels': [],
          'open': [],
          'url': 'https://fixture.invalid',
        },
      ]) {
        expect(
          MenuWindowPreferences.parse({...good, 'layout': layout}),
          isNull,
        );
      }
    },
  );
  test('local images require explicit selection; cancellation preserves current image', () async {
    final pending = Completer<Object?>();
    var calls = 0;
    final tools = MenuLocalToolsController((action, args) {
      calls++;
      expect(action, 'image');
      return pending.future;
    });
    expect(calls, 0);
    final work = tools.image();
    final again = tools.image();
    expect(calls, 1);
    pending.complete(Uint8List.fromList([1, 2, 3]));
    await work;
    await again;
    expect(tools.reference, [1, 2, 3]);
    tools.dispose();
  });
  test('late local image result after menu disposal is discarded', () async {
    final pending = Completer<Object?>();
    final tools = MenuLocalToolsController((_, _) => pending.future);
    final work = tools.image();
    tools.dispose();
    pending.complete(Uint8List.fromList([1]));
    await work;
    expect(tools.reference, isNull);
  });
  testWidgets('feature draft cannot cross a target scope', (tester) async {
    MenuFeatureView view(String scope) => MenuFeatureView.parse({
      'state': 'ready',
      'scope': scope,
      'buttons': [
        {'key': 'a1', 'label': '发送', 'input': '输入消息', 'limit': 1000},
      ],
    });
    await tester.pumpWidget(
      app(MenuFeaturePanel(view: view('s1'), onAction: (_, _) {})),
    );
    expect(view('s1').state, 'ready');
    expect(view('s1').buttons.length, 1);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'private draft');
    await tester.pumpWidget(
      app(MenuFeaturePanel(view: view('s2'), onAction: (_, _) {})),
    );
    expect(find.text('private draft'), findsNothing);
  });
  for (final scaled in [false, true]) {
    for (final bounds in const [
      Size(2560, 1440),
      Size(1600, 900),
      Size(960, 720),
    ]) {
      testWidgets(
        'all main tools open independently at $bounds scaled=$scaled without eager native work',
        (tester) async {
          size(tester, bounds);
          final calls = <String>[];
          await tester.pumpWidget(
            app(
              MediaQuery(
                data: MediaQueryData(
                  size: bounds,
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scaled ? 2 : 1),
                ),
                child: MenuBridgePreview(
                  visible: true,
                  onDismiss: () {},
                  onFeatureVisible: (_, _) {},
                  onFeatureAction: (_, _, _) {},
                  localCall: (action, _) async {
                    calls.add(action);
                    return null;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(calls, isEmpty);
          for (final tool in [
            'group',
            'room',
            'overlay',
            'image',
            'browser',
            'camera',
          ]) {
            await tester.ensureVisible(find.byKey(ValueKey('menu-tool-$tool')));
            await tester.tap(find.byKey(ValueKey('menu-tool-$tool')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: tool);
            // Windows now occlude the desktop dock. Move each newly opened
            // window clear before using another desktop shortcut.
            final id =
                const {
                  'group': 'organizations',
                  'room': 'rooms',
                  'overlay': 'hud',
                  'camera': 'screenshot',
                }[tool] ??
                tool;
            final panelRect = tester.getRect(
              find.byKey(ValueKey('menu-panel-$id')),
            );
            await tester.drag(
              find.byKey(ValueKey('menu-move-$id')),
              // Leave only a sliver; at 200% the desktop shortcut can begin
              // at x=100, while a tall organization window still covers it.
              Offset(-panelRect.right + 40, -panelRect.top),
            );
            await tester.pumpAndSettle();
          }
          for (final tool in [
            'organizations',
            'rooms',
            'hud',
            'image',
            'browser',
            'screenshot',
          ]) {
            expect(
              find.byKey(ValueKey('menu-panel-$tool'), skipOffstage: false),
              findsOneWidget,
            );
          }
          expect(calls, containsAll(['browserOpen', 'capture']));
          expect(calls, isNot(contains('image')));
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
  for (final browser in [false, true]) {
    testWidgets(
      'local tool remains usable in its minimum window browser=$browser',
      (tester) async {
        final tools = MenuLocalToolsController((_, _) async => null);
        final workspace = MenuWorkspaceController(
          scope: Object(),
          panels: const [],
        );
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 320,
                height: 200,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: browser
                      ? MenuLocalSettings(tools: tools, workspace: workspace)
                      : MenuImageTool(tools: tools),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        tools.dispose();
      },
    );
  }
}
