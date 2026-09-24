import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';

import 'menu_profiles_session_test.dart' show fixtureProfile;

import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart'
    show MenuInlineAvatar;

const channel = MethodChannel('starbridge/menu-surface');
Map<String, Object> snapshot(int opening, {bool wanted = true}) => {
  'opening': opening,
  'wanted': wanted,
  if (wanted) ...{
    'contextLabel': '隔离菜单测试',
    'returnLabel': '返回游戏',
    'settingsLabel': '菜单设置',
  },
};

Future<void> push(WidgetTester tester, Object value) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('snapshot', value)),
    (_) {},
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () =>
        TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
          disableAnimations: true,
        ),
  );
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue(),
  );
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final throws in [true, false]) {
    testWidgets(
      'friend intent exposes ${throws ? 'native failure' : 'missing acknowledgment'} and never repeats command',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 900);
        addTearDown(tester.view.reset);
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            if (call.method == 'friendsAction' && throws) {
              throw PlatformException(code: 'disconnected');
            }
            return call.method == 'ready' ? snapshot(0, wanted: false) : null;
          },
        );
        await tester.pumpWidget(const MenuOverlaySurfaceApp());
        await tester.pumpAndSettle();
        await push(tester, {
          ...snapshot(1),
          'workspacePreview': true,
          'liveFriends': true,
        });
        expect(calls.where((c) => c.method == 'friendsAction'), isEmpty);
        await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
        await tester.pumpAndSettle();
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('friendsView', {
              'opening': 1,
              'revision': 1,
              'payload': jsonEncode({
                'state': 'ready',
                'rows': [
                  {'name': 'Fixture', 'presence': 'online', 'key': 'f1'},
                ],
                'incoming': 0,
                'interactive': true,
                'busy': false,
                'requiresRefresh': false,
                'section': 'friends',
                'query': '',
                'feedback': '',
                'actions': {
                  'f1': ['remove'],
                },
              }),
            }),
          ),
          (_) {},
        );
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('f1')));
        await tester.tap(find.byKey(const ValueKey('f1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('friend-remove-f1')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 6));
        await tester.pump();
        final action = calls.where((c) => c.method == 'friendsAction').single;
        expect(action.arguments, {
          'opening': 1,
          'action': 'prepare',
          'key': 'f1',
          'value': 'remove',
        });
        expect(find.textContaining('操作结果尚未确认'), findsOneWidget);
        expect(find.textContaining('核对列表前暂不可'), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
        expect(calls.where((c) => c.method == 'friendsAction').length, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'composer forwards explicit intent and exposes native failure without losing text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 900);
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'commsCompose') {
          throw PlatformException(code: 'disconnected');
        }
        return call.method == 'ready' ? snapshot(0, wanted: false) : null;
      });
      await tester.pumpWidget(const MenuOverlaySurfaceApp());
      await tester.pumpAndSettle();
      await push(tester, {
        ...snapshot(1),
        'workspacePreview': true,
        'liveFriends': true,
        'liveComms': true,
      });
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('commsView', {
            'opening': 1,
            'revision': 1,
            'payload': jsonEncode({
              'state': 'ready',
              'name': 'Fixture',
              'profileKey': 'c1',
              'request': false,
              'hasOlder': false,
              'olderPage': false,
              'messages': [],
              'compose': true,
              'canSend': true,
              'locked': false,
              'draft': '',
              'draftRevision': 0,
              'delivery': 'idle',
            }),
          }),
        ),
        (_) {},
      );
      await tester.pump();
      final field = find.byKey(const ValueKey('menu-message-draft'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'unsaved');
      await tester.pump();
      final compose = calls.where((c) => c.method == 'commsCompose').single;
      expect(compose.arguments, {
        'opening': 1,
        'action': 'edit',
        'key': 'c1',
        'text': 'unsaved',
        'revision': 1,
      });
      expect(find.textContaining('通讯连接中断'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'unsaved');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('menu-message-send')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'comms opens on demand and rejects stale history after native hide',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 900);
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'ready' ? snapshot(0, wanted: false) : null;
      });
      Future<void> comms(
        int opening,
        int revision,
        Map<String, Object?> data,
      ) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('commsView', {
              'opening': opening,
              'revision': revision,
              'payload': jsonEncode(data),
            }),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await tester.pumpWidget(const MenuOverlaySurfaceApp());
      await tester.pumpAndSettle();
      await push(tester, {
        ...snapshot(1),
        'workspacePreview': true,
        'liveFriends': true,
        'liveComms': true,
      });
      expect(calls.where((c) => c.method == 'commsVisible'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'commsVisible');
      expect(calls.last.arguments, {'opening': 1, 'visible': true});
      await comms(1, 1, {
        'state': 'ready',
        'rows': [
          {
            'key': 'c1',
            'name': 'Fixture pilot',
            'time': '2026-01-01T00:00:00Z',
            'unread': 2,
            'request': false,
          },
        ],
      });
      await tester.tap(find.byKey(const ValueKey('menu-conversation-c1')));
      await tester.pump();
      expect(calls.last.method, 'commsAction');
      expect(calls.last.arguments, {
        'opening': 1,
        'action': 'select',
        'key': 'c1',
      });
      final history = <String, Object?>{
        'state': 'ready',
        'name': 'Fixture pilot',
        'profileKey': 'c1',
        'avatar': null,
        'request': false,
        'hasOlder': true,
        'olderPage': false,
        'messages': [
          {
            'incoming': true,
            'text': 'Fixture message',
            'time': '2026-01-01T00:00:00Z',
            'attachment': false,
          },
        ],
      };
      await comms(1, 3, history);
      expect(find.text('Fixture message'), findsOneWidget);
      Future<void> profile(
        int opening,
        int revision,
        Map<String, Object?> view,
      ) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('profileView', {
              'opening': opening,
              'revision': revision,
              'payload': jsonEncode({'window': 'p1', ...view}),
            }),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await tester.tap(find.byType(MenuInlineAvatar).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看个人页面'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('menu-panel-p1')), findsOneWidget);
      expect(calls.last.method, 'profileAction');
      expect(calls.last.arguments, {
        'opening': 1,
        'action': 'open',
        'window': 'p1',
        'source': 'comms',
        'key': 'c1',
      });
      expect(find.text('Fixture message'), findsOneWidget);
      await profile(1, 1, MenuProfileView.encode(fixtureProfile));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic profile'), findsOneWidget);
      final profileWindow = find.byKey(const ValueKey('menu-panel-p1'));
      final original = tester.getRect(profileWindow);
      await tester.drag(
        find.byKey(const ValueKey('menu-move-p1')),
        const Offset(60, 20),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(profileWindow).left, greaterThan(original.left));
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MenuInlineAvatar).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看个人页面'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        calls
            .where(
              (c) =>
                  c.method == 'profileAction' &&
                  (c.arguments as Map)['action'] == 'open',
            )
            .length,
        1,
      );
      expect(find.byKey(const ValueKey('menu-panel-p2')), findsNothing);
      await profile(1, 0, {'state': 'unavailable'});
      await profile(0, 2, {'state': 'unavailable'});
      expect(find.text('Synthetic profile'), findsOneWidget);
      await profile(1, 2, {'state': 'revoked'});
      expect(find.text('Synthetic profile'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('menu-close-p1')));
      await tester.pump();
      expect(calls.last.arguments, {
        'opening': 1,
        'action': 'close',
        'window': 'p1',
        'source': 'comms',
        'key': 'c1',
      });
      await profile(1, 3, MenuProfileView.encode(fixtureProfile));
      expect(find.text('Synthetic profile'), findsNothing);
      await comms(1, 2, {'state': 'unavailable'});
      expect(find.text('Fixture message'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-comms-back')));
      await tester.pump();
      expect(calls.last.arguments, {'opening': 1, 'action': 'back', 'key': ''});
      await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'friendsVisible');
      expect(calls.last.arguments, {'opening': 1, 'visible': true});
      expect(find.text('Fixture message'), findsOneWidget);
      expect(calls.where((c) => c.method == 'commsVisible').length, 1);
      await tester.tap(find.byKey(const ValueKey('menu-close-comms')));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'commsVisible');
      expect(calls.last.arguments, {'opening': 1, 'visible': false});
      await push(tester, snapshot(1, wanted: false));
      await comms(1, 9, history);
      await push(tester, {
        ...snapshot(2),
        'workspacePreview': true,
        'liveFriends': true,
        'liveComms': true,
      });
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      expect(find.text('Fixture message'), findsNothing);
      expect(find.text('正在读取通讯…'), findsOneWidget);
      expect(
        calls.any(
          (c) => c.method.contains('send') || c.method.contains('markRead'),
        ),
        false,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('live trial isolates demo and rejects late window/revision data', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'ready' ? snapshot(0, wanted: false) : null;
    });
    Future<void> friends(int opening, int revision, String name) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('friendsView', {
            'opening': opening,
            'revision': revision,
            'payload':
                '{"state":"ready","incoming":4,"rows":[{"name":"$name","presence":"unknown"}]}',
          }),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await tester.pumpWidget(const MenuOverlaySurfaceApp());
    await tester.pumpAndSettle();
    await push(tester, {
      ...snapshot(1),
      'workspacePreview': true,
      'liveFriends': true,
    });
    expect(find.text('远航者组织'), findsNothing);
    expect(find.text('好友申请'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'friendsVisible');
    expect(calls.last.arguments, {'opening': 1, 'visible': true});
    await friends(1, 2, 'Current');
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('状态未共享'), findsOneWidget);
    await friends(1, 1, 'Stale');
    await friends(0, 3, 'Old window');
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Stale'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-close-friends')));
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'opening': 1, 'visible': false});
    await push(tester, snapshot(1, wanted: false));
    await friends(1, 9, 'Hidden');
    await push(tester, {
      ...snapshot(2),
      'workspacePreview': true,
      'liveFriends': true,
    });
    await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
    await tester.pumpAndSettle();
    expect(find.text('Current'), findsNothing);
    expect(find.text('Hidden'), findsNothing);
    expect(find.text('正在读取好友…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'explicit visual preview hides clock and reopens without extra channels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'ready' ? snapshot(0, wanted: false) : null;
      });
      // The normal product entry accepts an explicit native preview request.
      await tester.pumpWidget(const MenuOverlaySurfaceApp());
      await tester.pumpAndSettle();
      expect(find.text('好友申请'), findsNothing);
      await push(tester, {...snapshot(1), 'workspacePreview': true});
      await tester.pumpAndSettle();
      expect(find.text('好友申请'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
      await tester.pumpAndSettle();
      expect(find.text('好友申请'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-local-clock')), findsOneWidget);
      expect(find.text('视觉预览 · 好友与通讯可展开 · 演示数据'), findsOneWidget);
      await push(tester, {
        ...snapshot(1, wanted: false),
        'workspacePreview': true,
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-local-clock')), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await push(tester, {...snapshot(2), 'workspacePreview': true});
      await tester.pumpAndSettle();
      expect(find.text('好友申请'), findsNothing);
      expect(find.byKey(const ValueKey('menu-local-clock')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls.last.method, 'dismiss');
      expect(calls.map((c) => c.method).toSet(), {
        'ready',
        'painted',
        'dismiss',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'handshake waits for configuration and acknowledges rendered opening',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'ready' ? snapshot(0, wanted: false) : null;
      });
      await tester.pumpWidget(const MenuOverlaySurfaceApp());
      await tester.pump();
      expect(find.text('隔离菜单测试'), findsNothing);
      expect(calls.map((e) => e.method), ['ready']);
      await push(tester, snapshot(1));
      expect(find.text('隔离菜单测试'), findsOneWidget);
      expect(calls.where((e) => e.method == 'painted').single.arguments, 1);
      await tester.tap(find.byKey(const ValueKey('menu-return')));
      expect(calls.last.method, 'dismiss');
      await push(tester, snapshot(1, wanted: false));
      expect(find.text('隔离菜单测试'), findsNothing);
      await push(tester, snapshot(1));
      expect(find.text('隔离菜单测试'), findsNothing);
      await push(tester, snapshot(2));
      expect(find.text('隔离菜单测试'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls.last.method, 'dismiss');
    },
  );

  testWidgets('late ready reply cannot resurrect dismissed content', (
    tester,
  ) async {
    final ready = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'ready' ? ready.future : null,
    );
    await tester.pumpWidget(const MenuOverlaySurfaceApp());
    await push(tester, snapshot(3, wanted: false));
    ready.complete(snapshot(2));
    await tester.pump();
    expect(find.text('隔离菜单测试'), findsNothing);
    await push(tester, {'opening': 4, 'wanted': true});
    expect(find.text('隔离菜单测试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing native bridge stays empty and does not bootstrap client',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => throw MissingPluginException(),
      );
      await tester.pumpWidget(const MenuOverlaySurfaceApp());
      await tester.pump();
      expect(find.byKey(const ValueKey('menu-return')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
