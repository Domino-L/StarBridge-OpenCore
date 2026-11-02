// 0.7.2 G9 交易消息 (approved preview trade-chat-preview, 2026-10-21): the
// view, its place in 好友与私信, and the detached window's relay.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/trade_chat_composition.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_ports.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_chat_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_chat_view.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/shared/trade_chat_slot.dart';

import '../../app/social_windows/social_window_test.dart' show Port, native;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

class ChatPort implements MarketplaceChatPort {
  final calls = <(String, MarketRow)>[];
  final pushes = StreamController<MarketRow>.broadcast(sync: true);
  String sendStatus = 'sent';
  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => pushes.stream;
  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) async {
    calls.add((operation, input));
    return switch (operation) {
      'conversations' => {
        'rows': [
          {
            'ref': 'p1',
            'name': 'Trader_Long_Handle_9000',
            'online': 1,
            'lastMessage': '今晚 9 点新巴贝奇可以吗？',
            'lastTime': DateTime.now().millisecondsSinceEpoch - 180000,
            'unread': 2,
          },
          {
            'ref': 'p2',
            'name': 'Kestrel_Fly',
            'online': 1,
            'lastMessage': '好的，我先发货',
            'unread': 0,
          },
          {
            'ref': 'p3',
            'name': 'RaiderMoon',
            'online': 0,
            'lastMessage': '[订单] 伊莫德 枪口稳定器',
            'banHistory': true,
            'banCount': 1,
            'banReason': '刷单',
            'banActive': false,
            'blockedByMe': true,
          },
        ],
      },
      'history' => {
        'rows': input['ref'] == 'p3'
            ? [
                {
                  'id': 2,
                  'mine': true,
                  'content': '只在 SCM 里交易，谢谢。',
                  'read': true,
                },
                {
                  'id': 1,
                  'mine': false,
                  'content': '加个微信聊吧 http://pay-scm.example/abc',
                  'risky': true,
                },
              ]
            : [
                {'id': 3, 'mine': false, 'content': '今晚 9 点新巴贝奇可以吗？'},
                {
                  'id': 2,
                  'mine': true,
                  'content': '有的，两块，单价 60 万。',
                  'read': true,
                },
                {
                  'id': 1,
                  'mine': false,
                  'content': '你好，科力晶还有吗？',
                  'quote': {
                    'type': 'order',
                    'orderNo': 'SO2026102100088',
                    'itemName': '科力晶（单个矿块）×2',
                    'amount': 1200000,
                    'statusText': '待发货',
                  },
                },
              ],
      },
      'send' =>
        sendStatus == 'sent'
            ? {
                'status': 'sent',
                'message': {'id': 9, 'mine': true, 'content': input['content']},
              }
            : {'status': sendStatus},
      _ => const {},
    };
  }
}

/// The primary's hall port: chat plus 解除拉黑 (blockRef while I block p3).
class RecordsChatPort extends ChatPort implements MarketplaceRecordsPort {
  final unblocked = <String>[];
  bool openScmMissing = false;
  @override
  bool get recordsSupported => true;
  @override
  Future<MarketRow> records(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add(('records.$operation', input));
    unblocked.add(input['ref'] as String);
    return {'confirmed': true};
  }

  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) async {
    if (operation == 'openScm' && openScmMissing) {
      calls.add((operation, input));
      throw const MarketplaceTradeError('marketplace.invalid_request');
    }
    final data = await super.chat(operation, input);
    if (operation != 'conversations') return data;
    return {
      'rows': [
        for (final row in data['rows'] as List)
          if ((row as Map)['ref'] == 'p3')
            unblocked.isEmpty
                ? {...row, 'blockRef': 'b3'}
                : {...row, 'blockedByMe': false}
          else
            row,
      ],
    };
  }
}

Future<void> _render(WidgetTester tester, String name) async {
  const out = String.fromEnvironment('OUT');
  if (out.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('chat-render')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _app(Widget child) => RepaintBoundary(
  key: const Key('chat-render'),
  child: scopedApp(
    Scaffold(backgroundColor: const Color(0xFF0B1118), body: child),
    InteractionSuite.scan,
  ),
);

Widget _header() =>
    const SizedBox(height: 36, child: Center(child: Text('交易消息')));

void main() {
  setUpAll(() async {
    if (const String.fromEnvironment('OUT').isEmpty) return;
    for (final (family, file) in [
      ('Source Sans 3', 'assets/fonts/SourceSans3VF-Upright.ttf'),
      ('Saira', 'assets/fonts/Saira-VF.ttf'),
      ('Rajdhani', 'assets/fonts/Rajdhani-SemiBold.ttf'),
      ('Source Han Sans CN', 'assets/fonts/SourceHanSansCN-VF.ttf'),
      ('Source Code Pro', 'assets/fonts/SourceCodeVF-Upright.ttf'),
    ]) {
      final bytes = File(file).readAsBytesSync();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  testWidgets('list, open, Enter sends once, pushes show at once', (
    tester,
  ) async {
    size(tester, const Size(1180, 720));
    final port = ChatPort();
    final c = MarketplaceChatController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _app(MarketplaceTradeChatView(c, header: _header())),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Trader_Long_Handle_9000'),
      findsOneWidget,
      reason: 'full handle, as on SCM',
    );
    expect(find.textContaining('封禁记录 1'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey(('trade-chat-conversation', 'p1'))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('科力晶（单个矿块）×2'),
      findsOneWidget,
      reason: 'order quote as a card',
    );
    expect(find.textContaining('已读'), findsOneWidget);
    await _render(tester, 'chat-list');

    await tester.enterText(
      find.byKey(const Key('trade-chat-input')),
      '可以，我到了在 TDD 门口等你',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      port.calls.where((x) => x.$1 == 'send').single.$2['content'],
      '可以，我到了在 TDD 门口等你',
    );
    expect(
      find.text('可以，我到了在 TDD 门口等你'),
      findsNWidgets(2),
      reason: 'shown from the reply, and as the last line in the list',
    );

    port.pushes.add({
      'kind': 'message',
      'ref': 'p1',
      'message': {'id': 10, 'mine': false, 'content': '到了'},
    });
    await tester.pump();
    expect(
      find.text('到了'),
      findsNWidgets(2),
      reason: 'a push shows without a read',
    );

    port.sendStatus = 'uncertain';
    await tester.enterText(find.byKey(const Key('trade-chat-input')), '货到了吗');
    await tester.tap(find.byKey(const Key('trade-chat-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会自动重发'), findsOneWidget);
    expect(port.calls.where((x) => x.$1 == 'send'), hasLength(2));
    await _render(tester, 'chat-states');

    // SCM counts UTF-16 (an emoji is 2): over 150 the text stays, with a hint.
    final long = '😀' * 76;
    await tester.enterText(find.byKey(const Key('trade-chat-input')), long);
    await tester.pump();
    expect(find.text('152/150'), findsOneWidget);
    expect(find.textContaining('表情算 2 个'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(port.calls.where((x) => x.$1 == 'send'), hasLength(2));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-chat-input')))
          .controller!
          .text,
      long,
    );
  });

  testWidgets('ban history and blocks: warned, sending disabled', (
    tester,
  ) async {
    size(tester, const Size(1180, 720));
    final c = MarketplaceChatController(ChatPort());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _app(MarketplaceTradeChatView(c, header: _header())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('trade-chat-conversation', 'p3'))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1 次封禁记录'), findsOneWidget);
    expect(find.textContaining('你已拉黑该用户'), findsOneWidget);
    expect(find.textContaining('含外部链接'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-chat-input')))
          .enabled,
      isFalse,
    );
    await _render(tester, 'chat-warn');
  });

  testWidgets('在 SCM 打开 goes to the conversation; 解除拉黑 in place', (
    tester,
  ) async {
    size(tester, const Size(1180, 720));
    final port = RecordsChatPort();
    final c = MarketplaceChatController(port);
    addTearDown(c.dispose);
    var home = 0;
    c.openScm = () => home++;
    await tester.pumpWidget(
      _app(MarketplaceTradeChatView(c, header: _header())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('trade-chat-conversation', 'p3'))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trade-chat-open-scm')));
    await tester.pumpAndSettle();
    expect(port.calls.last.$1, 'openScm');
    expect(port.calls.last.$2, {'ref': 'p3'});
    expect(home, 0, reason: 'the Host opens the conversation itself');
    port.openScmMissing = true;
    await tester.tap(find.byKey(const Key('trade-chat-open-scm')));
    await tester.pumpAndSettle();
    expect(home, 1, reason: 'an older Host: the SCM home page as before');

    expect(find.textContaining('举报与拉黑'), findsNothing);
    await _render(tester, 'chat-unblock');
    await tester.tap(find.byKey(const Key('trade-chat-unblock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-chat-unblock-cancel')));
    await tester.pumpAndSettle();
    expect(port.unblocked, isEmpty, reason: 'cancel sends nothing');
    await tester.tap(find.byKey(const Key('trade-chat-unblock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-chat-unblock-confirm')));
    await tester.pumpAndSettle();
    expect(port.unblocked, ['b3']);
    expect(
      find.textContaining('你已拉黑该用户'),
      findsNothing,
      reason: 'the list was read again',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-chat-input')))
          .enabled,
      isTrue,
    );
  });

  testWidgets('a trade opens its conversation with the order attached', (
    tester,
  ) async {
    size(tester, const Size(1180, 720));
    final port = ChatPort();
    final c = MarketplaceChatController(port);
    addTearDown(c.dispose);
    c.requestOpen(
      'p1',
      attach: const MarketChatAttachment(88, '科力晶（单个矿块）×2 · #TX2026102100009'),
    );
    await tester.pumpWidget(
      _app(MarketplaceTradeChatView(c, header: _header())),
    );
    await tester.pumpAndSettle();
    expect(c.openRef, 'p1');
    expect(find.byKey(const Key('trade-chat-attachment')), findsOneWidget);
    await _render(tester, 'chat-entry');
    await tester.enterText(find.byKey(const Key('trade-chat-input')), '可以');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(port.calls.where((x) => x.$1 == 'send').single.$2['orderId'], 88);
    expect(
      find.byKey(const Key('trade-chat-attachment')),
      findsNothing,
      reason: 'sent with the message',
    );
  });

  testWidgets('narrow: list first, then the conversation with a way back', (
    tester,
  ) async {
    size(tester, const Size(420, 720));
    final c = MarketplaceChatController(ChatPort());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _app(MarketplaceTradeChatView(c, header: _header())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-chat-input')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey(('trade-chat-conversation', 'p2'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-chat-input')), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-chat-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-chat-input')), findsNothing);
  });

  testWidgets('好友与私信 offers 交易消息; a request switches to it', (tester) async {
    size(tester, const Size(1180, 720));
    final c = MarketplaceChatController(ChatPort());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _app(
        withTradeChat(
          c,
          DirectMessagesPage(createPort: Port.new, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(('trade-chat-group', true))),
      findsOneWidget,
    );
    expect(find.byType(MarketplaceTradeChatView), findsNothing);
    await tester.tap(find.byKey(const ValueKey(('trade-chat-group', true))));
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceTradeChatView), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(('trade-chat-group', false))));
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceTradeChatView), findsNothing);
    c.requestOpen('p2');
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceTradeChatView), findsOneWidget);
    expect(c.openRef, 'p2');
    expect(
      TradeChatSlot.maybeOf(tester.element(find.byType(DirectMessagesPage))),
      isNotNull,
    );
    // 通知中心 → 交易私信: switch to the group, open nothing.
    await tester.tap(find.byKey(const ValueKey(('trade-chat-group', false))));
    await tester.pumpAndSettle();
    final reads = (c.port as ChatPort).calls.length;
    c.requestShow();
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceTradeChatView), findsOneWidget);
    expect(c.pendingRef, isNull, reason: 'consumed once');
    expect(
      (c.port as ChatPort).calls.skip(reads).map((x) => x.$1),
      isNot(contains('history')),
    );
  });

  testWidgets(
    'detached window: reads relay through rpc, pushes ride the snapshot',
    (tester) async {
      const channel = MethodChannel('starbridge/messages-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final snapshots = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'snapshot' || call.method == 'show') {
          snapshots.add(call.arguments as Map);
        }
        return call.method == 'show' ? true : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final port = ChatPort();
      final chat = MarketplaceChatController(port);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: Port(),
        inbox: NotificationInboxController(null),
        navigate: (_) async {},
        tradeChat: chat,
      );
      await binding.open();
      Map view() => jsonDecode(snapshots.last['view'] as String) as Map;
      expect(view()['tradeChat'], isTrue);

      final rows = await native(channel.name, 'rpc', {
        'opening': binding.snapshot['opening'],
        'scope': binding.scope,
        'op': 'trade',
        'operation': 'conversations',
        'input': <String, Object?>{},
      }) as Map;
      expect((rows['rows'] as List).first['name'], 'Trader_Long_Handle_9000');
      await expectLater(
        native(channel.name, 'rpc', {
          'opening': binding.snapshot['opening'],
          'scope': binding.scope,
          'op': 'trade',
          'operation': 'close',
        }),
        throwsA(isA<PlatformException>()),
        reason: 'only the window operations are relayed',
      );
      await expectLater(
        native(channel.name, 'rpc', {
          'opening': binding.snapshot['opening'],
          'scope': binding.scope,
          'op': 'trade',
          'records': true,
          'operation': 'unblock',
          'input': {'ref': 'b3'},
        }),
        throwsA(isA<PlatformException>()),
        reason: 'unblock only where the primary port can',
      );

      port.pushes.add({
        'kind': 'message',
        'ref': 'p1',
        'message': {'id': 10, 'content': '到了'},
      });
      await tester.pump(const Duration(milliseconds: 100));
      final pushed = view()['tradePushes'] as List;
      expect(pushed.single['serial'], 1);
      expect(pushed.single['push']['message']['content'], '到了');

      chat.requestOpen('p2', attach: const MarketChatAttachment(88, '科力晶 ×2'));
      await tester.pump();
      expect(view()['tradeRequest'], {
        'serial': 1,
        'ref': 'p2',
        'orderId': 88,
        'label': '科力晶 ×2',
      });
      binding.dispose();
      chat.dispose();
      await tester.pump(const Duration(seconds: 3));
    },
  );

  test('window: the first snapshot is a baseline; a gap reads again', () async {
    final port = WindowTradeChatPort((_, _) async => const {});
    final seen = <MarketRow>[];
    port.chatPushes.listen(seen.add);
    Map entry(int serial) => {
      'serial': serial,
      'push': {
        'kind': 'message',
        'ref': 'p1',
        'message': {'id': serial},
      },
    };
    port.accept([entry(1), entry(2), entry(3)]);
    await pumpEventQueue();
    expect(seen, isEmpty, reason: 'old pushes are not replayed on (re)opening');
    port.accept([entry(2), entry(3), entry(4)]);
    await pumpEventQueue();
    expect(seen.map((p) => (p['message'] as Map)['id']), [4]);
    port.accept([entry(30), entry(31)]);
    await pumpEventQueue();
    expect(seen[1], {'kind': 'resync'}, reason: 'pushes 5..29 were missed');
    expect(seen.skip(2).map((p) => (p['message'] as Map)['id']), [30, 31]);
    await port.close();
  });

  testWidgets('window: 在 SCM 打开 and 解除拉黑 relay to the primary', (tester) async {
    const channel = MethodChannel('starbridge/messages-primary');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'show' ? true : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final port = RecordsChatPort();
    final chat = MarketplaceChatController(port);
    final binding = SocialWindowBinding(
      kind: 'messages',
      messages: Port(),
      inbox: NotificationInboxController(null),
      navigate: (_) async {},
      tradeChat: chat,
    );
    await binding.open();
    final window = WindowTradeChatPort(
      (op, args) => native(channel.name, 'rpc', {
        'opening': binding.snapshot['opening'],
        'scope': binding.scope,
        'op': op,
        ...args,
      }),
    );
    await window.chat('openScm', {'ref': 'p3'});
    expect(port.calls.last.$1, 'openScm');
    expect(await window.records('unblock', {'ref': 'b3'}), {'confirmed': true});
    expect(port.unblocked, ['b3']);
    await expectLater(
      window.records('blocklist'),
      throwsA(isA<MarketplaceTradeError>()),
      reason: 'no other records operation is relayed',
    );
    binding.dispose();
    chat.dispose();
  });

  testWidgets(
    'window: a delivered open request is consumed; pushes are coalesced',
    (tester) async {
      const channel = MethodChannel('starbridge/messages-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final snapshots = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'snapshot' || call.method == 'show') {
          snapshots.add(call.arguments as Map);
        }
        return call.method == 'show' ? true : null;
      });
      final port = ChatPort();
      final chat = MarketplaceChatController(port);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: Port(),
        inbox: NotificationInboxController(null),
        navigate: (_) async {},
        tradeChat: chat,
      );
      Map view() => jsonDecode(snapshots.last['view'] as String) as Map;
      chat.requestOpen('p2');
      await binding.open();
      expect(
        view()['tradeRequest'],
        isNotNull,
        reason: 'the opening carries it',
      );
      expect(
        chat.pendingRef,
        isNull,
        reason: 'consumed once the window has it',
      );
      final before = snapshots.length;
      for (var i = 0; i < 10; i++) {
        port.pushes.add({
          'kind': 'message',
          'ref': 'p1',
          'message': {'id': 100 + i},
        });
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        snapshots.length - before,
        inInclusiveRange(1, 2),
        reason: 'one snapshot for the burst',
      );
      expect((view()['tradePushes'] as List).length, 10);
      expect(
        view().containsKey('tradeRequest'),
        isFalse,
        reason: 'not sent again',
      );
      binding.dispose();
      chat.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
