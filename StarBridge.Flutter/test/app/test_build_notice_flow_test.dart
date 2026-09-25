import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/app/runtime/test_build_notice_flow.dart';
import 'package:starbridge_flutter/app/runtime/test_build_notice_copy.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../features/settings/local_privacy_page_test.dart' show app, viewport;

void main() {
  testWidgets(
    'full notice scrolls in a small window while actions remain accessible',
    (tester) async {
      final h = Harness();
      await h.mount(tester, size: const Size(800, 600));
      expect(
        tester.getRect(find.byKey(const Key('test-build-accept'))).bottom,
        lessThanOrEqualTo(600),
      );
      final body = find.text(testBuildNoticeBody(const Locale('zh', 'CN')));
      expect(body, findsOneWidget);
      final scroll = find.ancestor(
        of: body,
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(scroll, const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(find.text('查看完整客户端许可').hitTestable(), findsOneWidget);
      expect(h.accepts, 0);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );
  test('Simplified Chinese notice preserves the seven approved paragraphs', () {
    final paragraphs = (jsonDecode(
      File('test/fixtures/test-build-notice.zh-CN.json').readAsStringSync(),
    ) as List).cast<String>();
    expect(paragraphs, hasLength(7));
    expect(
      testBuildNoticeBody(const Locale('zh', 'CN')),
      paragraphs.join('\n\n'),
    );
  });
  testWidgets('accepted WPF or prior Flutter receipt never opens a notice', (
    tester,
  ) async {
    final h = Harness()..acknowledged = true;
    await h.mount(tester);
    expect(find.byKey(const Key('test-build-notice')), findsNothing);
    expect(h.flow.blocksPrompts, isFalse);
    expect(h.accepts, 0);
    await h.close(tester);
  });
  testWidgets(
    'startup account generation change rechecks the existing receipt',
    (tester) async {
      final h = Harness()
        ..acknowledged = true
        ..advanceDuringFirstRead = true;
      await h.mount(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test-build-notice')), findsNothing);
      expect(h.reads, 2);
      expect(h.flow.blocksPrompts, isFalse);
      expect(h.accepts, 0);
      await h.close(tester);
    },
  );
  testWidgets(
    'first use explicitly acknowledges, then a new flow does not repeat',
    (tester) async {
      final h = Harness();
      await h.mount(tester);
      expect(find.byKey(const Key('test-build-notice')), findsOneWidget);
      expect(find.text('测试版使用须知'), findsOneWidget);
      expect(find.text('我已阅读并理解，继续'), findsOneWidget);
      expect(find.textContaining('确认记录保存在本机'), findsNothing);
      expect(find.textContaining('核对 Windows 数字签名'), findsOneWidget);
      expect(h.accepts, 0);
      expect(h.flow.blocksPrompts, isTrue);
      await tester.tap(find.byKey(const Key('test-build-accept')));
      await tester.pumpAndSettle();
      expect(h.accepts, 1);
      expect(h.flow.blocksPrompts, isFalse);
      h.flow.dispose();
      h.createFlow();
      h.flow.wake();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test-build-notice')), findsNothing);
      expect(h.accepts, 1);
      await h.close(tester);
    },
  );
  testWidgets('unknown receipt retries silently without writing acceptance', (
    tester,
  ) async {
    final h = Harness()
      ..acknowledged = true
      ..unknownReads = 1;
    await h.mount(tester);
    expect(find.byKey(const Key('test-build-notice')), findsNothing);
    expect(h.flow.blocksPrompts, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(h.reads, 2);
    expect(h.accepts, 0);
    expect(h.flow.blocksPrompts, isFalse);
    expect(find.byKey(const Key('test-build-notice')), findsNothing);
    await h.close(tester);
  });
  testWidgets('persistent read failure is bounded and never grants consent', (
    tester,
  ) async {
    final h = Harness()..unknownReads = 20;
    await h.mount(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    expect(h.reads, 3);
    expect(h.accepts, 0);
    expect(h.flow.blocksPrompts, isTrue);
    expect(find.byKey(const Key('test-build-notice')), findsOneWidget);
    await h.close(tester);
  });
  testWidgets('disposing a pending read retry cancels subsequent requests', (
    tester,
  ) async {
    final h = Harness()..unknownReads = 20;
    await h.mount(tester);
    expect(h.reads, 1);
    h.flow.dispose();
    await tester.pump(const Duration(seconds: 3));
    expect(h.reads, 1);
    expect(h.accepts, 0);
    await h.close(tester);
  });
  testWidgets(
    'failed acknowledgement stays visible and exit does not grant consent',
    (tester) async {
      final h = Harness()..fail = true;
      await h.mount(tester);
      await tester.tap(find.byKey(const Key('test-build-accept')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('test-build-notice')), findsOneWidget);
      expect(h.acknowledged, isFalse);
      expect(find.textContaining('请重试'), findsOneWidget);
      expect(find.textContaining('数据目录'), findsNothing);
      await tester.tap(find.text('退出应用'));
      await tester.pumpAndSettle();
      expect(h.exits, 1);
      expect(h.acknowledged, isFalse);
      await h.close(tester);
    },
  );
}

class Harness {
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 1,
  );
  late StreamSubscription<BridgeEnvelope> subscription;
  final queue = StartupPromptQueue(
    quietPeriod: const Duration(milliseconds: 1),
  );
  late TestBuildNoticeFlow flow;
  bool acknowledged = false, fail = false;
  bool advanceDuringFirstRead = false;
  int accepts = 0, exits = 0, reads = 0, unknownReads = 0;
  void createFlow() => flow = TestBuildNoticeFlow(
    session: session,
    queue: queue,
    ready: () => true,
    onExit: () async {
      exits++;
    },
    onChanged: () {},
  );
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(800, 900),
  }) async {
    viewport(tester, size);
    subscription = pair.host.incoming.listen((request) {
      if (request.messageType != 'request') return;
      if (request.name == 'legal.readTestBuildNotice') {
        reads++;
        if (advanceDuringFirstRead && reads == 1) {
          session.advanceGeneration(session.activeGeneration + 1);
          return;
        }
      }
      if (request.name == 'legal.acceptTestBuildNotice') {
        accepts++;
        if (!fail) acknowledged = true;
      }
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload:
                request.name == 'legal.readTestBuildNotice' &&
                    reads <= unknownReads
                ? const {'schemaVersion': 1}
                : {
                    'schemaVersion': 1,
                    'termsVersion': '2026-08-01-v3',
                    'acknowledged': acknowledged,
                  },
          ),
        ),
      );
    });
    createFlow();
    await tester.pumpWidget(
      app(
        Navigator(
          observers: [queue],
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );
    flow.wake();
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    flow.dispose();
    queue.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
  }
}
