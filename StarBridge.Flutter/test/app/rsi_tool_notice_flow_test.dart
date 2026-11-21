import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/legal/usage_terms_sections.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/help_support_strings.dart';
import 'package:starbridge_flutter/app/runtime/rsi_tool_notice_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/platform/window/rsi_tool_notice_receipt.dart';

import '../features/settings/local_privacy_page_test.dart' show app, viewport;

void main() {
  final approved = (jsonDecode(
    File('test/fixtures/rsi-tool-notice.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final locales = [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ];
  for (var i = 0; i < locales.length; i++) {
    final locale = locales[i];
    testWidgets(
      'approved copy is identical across all three surfaces $locale',
      (tester) async {
        viewport(tester, const Size(1000, 800));
        final copy = rsiToolNoticeCopy(locale);
        expect(copy.title, approved[i]['title']);
        expect(copy.body, approved[i]['body']);
        expect(copy.button, approved[i]['button']);
        expect(
          AppStrings.resolve(locale).text('help.legal.safety.body'),
          copy.body,
        );
        expect(copy.body, contains('AttachThreadInput'));
        expect(copy.body, contains('RegisterHotKey'));
        expect(
          copy.body,
          contains('https://support.robertsspaceindustries.com/'),
        );
        if (i == 0) expect(copy.body, contains('是否符合 RSI 条款由 CIG 判断'));
        await tester.pumpWidget(
          app(
            const SingleChildScrollView(
              child: UsageTermsSections(license: Text('Synthetic license')),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const Key('usage-terms-rsi-notice')),
              )
              .data,
          copy.body,
        );
        expect(find.text(copy.title), findsOneWidget);
        await tester.pumpWidget(
          app(RsiToolNoticeDialog(acknowledge: () async {}), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(find.byType(SelectableText)).data,
          copy.body,
        );
        expect(find.text(copy.title), findsOneWidget);
        expect(find.text(copy.button), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('terms version remains unchanged', () {
    final source = File('lib/app/runtime/test_build_notice_flow.dart')
        .readAsStringSync();
    expect(source, contains("'termsVersion'] == '2026-11-05-v5'"));
    expect(source, contains("'termsVersion': '2026-11-05-v5'"));
  });

  testWidgets(
    'first launch records read receipt and next launch stays silent',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      expect(find.byKey(const Key('rsi-tool-notice')), findsOneWidget);
      expect(h.store.writes, 0);
      expect(h.flow.blocksPrompts, isTrue);
      await h.confirm(tester);
      expect(h.store.writes, 1);
      expect(h.store.seen, isTrue);
      expect(h.flow.blocksPrompts, isFalse);
      expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
      h.restart();
      await h.tick(tester);
      expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
      expect(h.store.writes, 1);
      await h.close(tester);
    },
  );

  testWidgets('existing receipt does not open or write', (tester) async {
    final h = _Harness()..store.seen = true;
    await h.mount(tester);
    expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
    expect(h.store.writes, 0);
    await h.close(tester);
  });

  testWidgets('terms must finish before notice; notice precedes onboarding', (
    tester,
  ) async {
    final h = _Harness()..termsAccepted = false;
    await h.mount(tester);
    expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
    expect(h.store.reads, 0);
    var onboarded = false;
    h.queue.enqueue(
      'onboarding',
      priority: 50,
      eligible: () => !h.flow.blocksPrompts,
      show: () async {
        onboarded = true;
      },
    );
    h.queue.enqueue(
      'terms',
      priority: 0,
      eligible: () => true,
      show: () async {
        h.termsAccepted = true;
        h.flow.wake();
      },
    );
    await h.tick(tester);
    expect(find.byKey(const Key('rsi-tool-notice')), findsOneWidget);
    expect(onboarded, isFalse);
    await h.confirm(tester);
    expect(onboarded, isTrue);
    await h.close(tester);
  });

  for (final failRead in [false, true]) {
    testWidgets(
      'failed receipt write closes, retries next launch read=$failRead',
      (tester) async {
        final h = _Harness()
          ..store.failWrite = true
          ..store.failRead = failRead;
        await h.mount(tester);
        expect(find.byKey(const Key('rsi-tool-notice')), findsOneWidget);
        await h.confirm(tester);
        expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
        expect(h.store.seen, isFalse);
        h.flow.wake();
        await h.tick(tester);
        expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
        h.restart();
        await h.tick(tester);
        expect(find.byKey(const Key('rsi-tool-notice')), findsOneWidget);
        await h.close(tester);
      },
    );
  }

  testWidgets('unresponsive write cannot trap the user', (tester) async {
    final h = _Harness()..store.hangWrite = true;
    await h.mount(tester);
    await tester.tap(find.byKey(const Key('rsi-tool-notice-got-it')));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
    expect(h.store.seen, isFalse);
    await h.close(tester);
  });

  testWidgets('barrier, back and Escape cannot dismiss the notice', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rsi-tool-notice')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rsi-tool-notice')), findsOneWidget);
    expect(h.store.writes, 0);
    await h.close(tester);
  });

  testWidgets('disposing during an unread query cancels its timeout', (
    tester,
  ) async {
    final h = _Harness()..store.hangRead = true;
    await h.mount(tester);
    expect(h.store.reads, 1);
    expect(find.byKey(const Key('rsi-tool-notice')), findsNothing);
    await h.close(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform adapter uses only the versioned local receipt', (
    tester,
  ) async {
    const channel = MethodChannel('starbridge/rsi-tool-notice');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'read' ? true : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    const receipt = MethodChannelRsiToolNoticeReceipt();
    expect(await receipt.read(), isTrue);
    await receipt.markSeen();
    expect(calls.map((c) => c.method), ['read', 'markSeen']);
    expect(calls.every((c) => c.arguments == RsiToolNoticeReceipt.key), isTrue);
    final native = File('windows/runner/rsi_tool_notice_store.h')
        .readAsStringSync();
    expect(native, contains('"${RsiToolNoticeReceipt.key}"'));
  });
}

final class _Receipt implements RsiToolNoticeReceipt {
  bool seen = false,
      failWrite = false,
      failRead = false,
      hangWrite = false,
      hangRead = false;
  int reads = 0, writes = 0;
  @override
  Future<bool> read() async {
    reads++;
    if (failRead) throw StateError('Synthetic read failure');
    if (hangRead) return Completer<bool>().future;
    return seen;
  }

  @override
  Future<void> markSeen() async {
    writes++;
    if (failWrite) throw StateError('Synthetic disk failure');
    if (hangWrite) return Completer<void>().future;
    seen = true;
  }
}

final class _Harness {
  final store = _Receipt();
  final queue = StartupPromptQueue(
    quietPeriod: const Duration(milliseconds: 1),
  );
  bool termsAccepted = true;
  late RsiToolNoticeFlow flow;
  void create() => flow = RsiToolNoticeFlow(
    receipt: store,
    queue: queue,
    ready: () => termsAccepted,
    onChanged: () {},
  );
  void restart() {
    flow.dispose();
    create();
    flow.wake();
  }

  Future<void> tick(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester) async {
    viewport(tester, const Size(800, 600));
    create();
    await tester.pumpWidget(
      app(
        Navigator(
          observers: [queue],
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      ),
    );
    flow.wake();
    await tick(tester);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('rsi-tool-notice-got-it')));
    await tick(tester);
  }

  Future<void> close(WidgetTester tester) async {
    flow.dispose();
    queue.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
}
