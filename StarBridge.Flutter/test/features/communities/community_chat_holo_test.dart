import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_workspace_frame.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';

import 'community_chat_controller_test.dart' show FakeChat;
import '../friends/social_layout_test.dart' show loadFonts;

final _capture = Platform.environment['STARBRIDGE_CAPTURE_HOLO'] == '1';

Map<String, Object?> _message(
  int sequence,
  String callsign,
  String text,
  DateTime at, {
  bool self = false,
}) => {
  'sequence': sequence,
  'messageRef': sequence.toRadixString(16).padLeft(32, '0'),
  'senderRef': callsign.hashCode.toRadixString(16).padLeft(32, 'e'),
  'senderCallsign': callsign,
  'senderGameId': '',
  'senderRoleTitle': '成员',
  'senderRoleColor': '#29AFFF',
  'text': text,
  'createdAt': at.toUtc().toIso8601String(),
  'isSelf': self,
  'hasAvatar': false,
  'hasAttachment': false,
};

Future<void> _show(WidgetTester tester, {bool holo = true}) async {
  tester.view.physicalSize = const Size(1200, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 0, 30);
  final port = FakeChat()
    ..next = CommunityChatPage.parse({
      'schemaVersion': 1,
      'targetRef': 'a' * 32,
      'unreadCount': 0,
      'latestSequence': 14,
      'oldestSequence': 10,
      'canSend': true,
      'hasOlder': false,
      'serverTime': now.toUtc().toIso8601String(),
      'messages': [
        _message(
          10,
          'Kestrel',
          '有人要一起跑 Ruin 站的悬赏吗？',
          today.subtract(const Duration(hours: 3)),
        ),
        _message(11, 'Rook', '我在派罗，十分钟后到。', today),
        _message(
          12,
          '多米诺',
          '今晚先在新巴贝奇集合，准备好后统一出发。',
          today.add(const Duration(minutes: 2)),
          self: true,
        ),
        _message(
          14,
          'Nova',
          '收到，我 20 点上线。',
          today.add(const Duration(minutes: 5)),
        ),
      ],
    });
  addTearDown(port.changes.close);
  final panel = CommunityChatPanel(
    port: port,
    targetRef: 'a' * 32,
    name: '主舰队',
    onBack: () {},
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('chat-holo-capture'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: holo ? OrganizationWorkspaceSurface(child: panel) : panel,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    await loadFonts();
    await (FontLoader('Source Code Pro')
          ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
        .load();
  });

  testWidgets('organization chat drops bubbles and separates days', (
    tester,
  ) async {
    await _show(tester);
    // No decorative English kicker (user 2026-10-29).
    expect(find.text('COMMS'), findsNothing);
    expect(find.text('主舰队 · 组织聊天'), findsOneWidget);
    // The first message is from yesterday or earlier today; a later day
    // starts with its own separator.
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('0/1000'), findsOneWidget);
    // No bubbles, but the general chat rule holds: others on the left,
    // your own messages on the right (user 10-23).
    final rook = tester.getTopRight(find.text('我在派罗，十分钟后到。'));
    final self = tester.getTopRight(find.text('今晚先在新巴贝奇集合，准备好后统一出发。'));
    expect(self.dx, greaterThan(rook.dx + 200));
    expect(tester.takeException(), isNull);
    if (_capture) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject(
          find.byKey(const ValueKey('chat-holo-capture')),
        ) as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/reviews').create(recursive: true);
        await File('build/reviews/holo-chat.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('chat outside an organization surface keeps its bubbles', (
    tester,
  ) async {
    await _show(tester, holo: false);
    expect(find.text('COMMS'), findsNothing);
    expect(find.text('今天'), findsNothing);
  });
}
