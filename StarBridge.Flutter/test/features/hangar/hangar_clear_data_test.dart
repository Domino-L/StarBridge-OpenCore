import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_controller.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_copy.dart';

import 'hangar_reader_test.dart' show app, BrowserFake, PreviewFake;

Finder control(String key) => find.byKey(Key(key));

void main() {
  Future<AccountModule> enter(WidgetTester tester, BrowserFake browser) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    await account.initialize();
    await tester.pumpWidget(
      app(
        HangarPage(
          account: account,
          previewFactory: PreviewFake.new,
          browserFactory: () => browser,
        ),
      ),
    );
    await tester.tap(control('hangar-open-reader'));
    await tester.pumpAndSettle();
    return account;
  }

  // Every clear outcome now ends with an explicit result dialog.
  Future<void> dismissResult(WidgetTester tester) async {
    expect(control('hangar-clear-result-ok'), findsOneWidget);
    await tester.tap(control('hangar-clear-result-ok'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'clear button confirms consequences and clears only after confirmation',
    (tester) async {
      final browser = BrowserFake();
      final account = await enter(tester, browser);
      expect(find.text('退出 RSI 登录并清除数据'), findsOneWidget);
      await tester.tap(control('hangar-reader-clear'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '这会退出机库读取里的 RSI 登录，并删除这台电脑上机库读取保存的浏览器数据（登录状态、Cookie、缓存）。已保存到本机的舰船不受影响。',
        ),
        findsOneWidget,
      );
      expect(browser.clears, 0);
      await tester.tap(control('hangar-clear-confirm'));
      await tester.pumpAndSettle();
      expect(browser.clears, 1);
      await dismissResult(tester);
      expect(find.text('已退出并清除'), findsOneWidget);
      expect(control('hangar-browser-viewport'), findsNothing);
      expect(
        browser.opens,
        1,
        reason: 'Clearing must not reopen RSI automatically',
      );
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    },
  );

  testWidgets('cancelling confirmation does not clear data', (tester) async {
    final browser = BrowserFake();
    final account = await enter(tester, browser);
    await tester.tap(control('hangar-reader-clear'));
    await tester.pumpAndSettle();
    await tester.tap(control('hangar-clear-cancel'));
    await tester.pumpAndSettle();
    expect(browser.clears, 0);
    expect(control('hangar-browser-viewport'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
  });

  for (final code in ['clear_busy', 'clear_unsafe', 'clear_failed']) {
    testWidgets('$code stays visible and the clear button can retry', (
      tester,
    ) async {
      final browser = BrowserFake()..clearFailure = code;
      final account = await enter(tester, browser);
      await tester.tap(control('hangar-reader-clear'));
      await tester.pumpAndSettle();
      await tester.tap(control('hangar-clear-confirm'));
      await tester.pumpAndSettle();
      final copy = HangarReaderCopy(tester.element(find.byType(HangarPage)));
      await dismissResult(tester);
      expect(find.text(copy.status(code)), findsOneWidget);
      expect(find.text('已退出并清除'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(copy.status(code)), findsOneWidget);
      browser.clearFailure = null;
      await tester.tap(control('hangar-reader-clear'));
      await tester.pumpAndSettle();
      await tester.tap(control('hangar-clear-confirm'));
      await tester.pumpAndSettle();
      expect(browser.clears, 2);
      await dismissResult(tester);
      expect(find.text('已退出并清除'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    });
  }

  testWidgets('clear is disabled while reading', (tester) async {
    final pending = Completer<Map<String, Object?>>();
    final browser = BrowserFake()..pendingCapture = pending;
    final account = await enter(tester, browser);
    await tester.tap(control('hangar-reader-action'));
    await tester.pump();
    final button = tester.widget<StarBridgeActionButton>(
      find.ancestor(
        of: find.text('退出 RSI 登录并清除数据'),
        matching: find.byType(StarBridgeActionButton),
      ),
    );
    expect(button.onActivate, isNull);
    await tester.tap(control('hangar-reader-clear'));
    await tester.pump();
    expect(control('hangar-clear-confirm'), findsNothing);
    expect(browser.clears, 0);
    pending.complete({});
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    account.dispose();
  });

  test('controller rejects clearing during an active read', () async {
    final pending = Completer<Map<String, Object?>>();
    final browser = BrowserFake()..pendingCapture = pending;
    final reader = HangarReaderController(browser, PreviewFake());
    await reader.open();
    final reading = reader.read();
    await Future<void>.delayed(Duration.zero);
    await reader.clearData();
    expect(browser.clears, 0);
    await reader.cancel();
    pending.complete({});
    await reading;
    await reader.clearData();
    expect(browser.clears, 1);
    expect(reader.phase, 'cleared');
    reader.dispose();
  });
}
