import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import '../../features/friends/social_layout_test.dart'
    show size, capture, loadFonts;

Map<String, Object?> snapshot({
  int opening = 1,
  int revision = 1,
  String name = '远航者',
}) => {
  'opening': opening,
  'revision': revision,
  'view': jsonEncode({
    'state': 'ready',
    'scope': 'friends$opening',
    'interactive': true,
    'section': 'friends',
    'query': '',
    'feedback': '',
    'busy': false,
    'requiresRefresh': false,
    'incoming': 0,
    'identity': {'name': name, 'handle': 'Pathfinder'},
    'self': {
      'key': 'self1',
      'status': 'presence.online',
      'change': true,
      'busy': false,
      'failed': false,
    },
    'chatKeys': ['f1', 'f2', 'f3', 'f4'],
    'rows': [
      {'name': '北辰', 'presence': 'inGame', 'key': 'f1'},
      {'name': '白鸦', 'presence': 'online', 'key': 'f2'},
      {'name': '回声', 'presence': 'away', 'key': 'f3'},
      {'name': '长夜', 'presence': 'offline', 'key': 'f4'},
      {'name': '新朋友', 'presence': 'unknown', 'key': 'f5'},
    ],
    'actions': {
      'f1': ['remove', 'block'],
    },
  }),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  const channel = MethodChannel('starbridge/friends-surface');
  testWidgets(
    'reuses roster at narrow size and routes chat without credentials',
    (tester) async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'ready' ? snapshot() : true;
      });
      size(tester, const Size(392, 640));
      final shot = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: shot, child: const FriendsWindowApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('远航者'), findsOneWidget);
      expect(find.text('游戏中'), findsOneWidget);
      expect(
        find.text('应用在线'),
        findsNWidgets(2),
      ); // Own state plus online friend.
      expect(find.text('离线'), findsNWidgets(2));
      expect(find.text('状态未共享'), findsNothing);
      expect(tester.takeException(), isNull);
      final clientTokens = FutureRestraintStyle.resolve(AppearanceMode.dark);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        clientTokens.surfaces.raised.fill,
      );
      final frame = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('friends-window-frame')),
      );
      expect(frame.position, DecorationPosition.foreground);
      final border = (frame.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, clientTokens.surfaces.windowFrame);
      expect(
        border,
        Border.all(
          color: clientTokens.surfaces.windowFrame,
          width: clientTokens.stroke.hairline,
        ),
      );
      await capture(tester, shot, 'friends-detached-392');
      expect(find.text('好友'), findsOneWidget);
      for (final entry in {
        '最小化': 'minimize',
        '最大化': 'toggleMaximize',
        '关闭好友窗口': 'close',
      }.entries) {
        await tester.tap(find.byTooltip(entry.key));
        await tester.pumpAndSettle();
        expect(
          calls.lastWhere((c) => c.method == 'windowControl').arguments,
          entry.value,
        );
      }
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('windowState', true),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('还原'), findsOneWidget);
      await tester.tap(find.byTooltip('还原'));
      await tester.pumpAndSettle();
      expect(
        calls.lastWhere((c) => c.method == 'windowControl').arguments,
        'toggleMaximize',
      );
      await tester.tap(find.byKey(const ValueKey('friend-open-f1')));
      await tester.pumpAndSettle();
      final action =
          calls.lastWhere((call) => call.method == 'action').arguments as Map;
      expect(action['action'], 'chat');
      expect(action['key'], 'f1');
      expect(action['opening'], 1);
      expect(action['scope'], 'friends1');
      expect(action.containsKey('reference'), false);
      await tester.tap(find.text('打开最近聊天'));
      await tester.pumpAndSettle();
      expect(
        (calls.lastWhere((c) => c.method == 'action').arguments
            as Map)['action'],
        'messages',
      );
      // Small / enlarged text uses the component's scrolling fallback, not overflow.
      tester.view.physicalSize = const Size(344, 380);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
