import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_controller.dart';

import 'hangar_reader_test.dart' show app, result, BrowserFake, PreviewFake;

Finder control(String key) => find.byKey(Key(key));

// The RSI sign-in is remembered only when the user ticks it on the reader
// page. Not remembering is the default; native clears on close.
void main() {
  Future<HangarReaderController> read(
    BrowserFake browser,
    Map<String, Object?> outcome,
  ) async {
    final preview = PreviewFake()..results = [outcome];
    final reader = HangarReaderController(browser, preview);
    await reader.open();
    expect(reader.browserOpen, isTrue);
    await reader.read();
    return reader;
  }

  test('not remembering is the default when native has no choice', () async {
    final browser = BrowserFake()..remembered = false;
    final reader = HangarReaderController(browser, PreviewFake());
    expect(reader.remember, isNull);
    await reader.open();
    expect(reader.remember, isFalse);
    reader.dispose();
  });

  for (final outcome in [
    {...result('complete'), 'canSave': true},
    result('needsReview'),
    result('pageChanged'),
    result('identityMismatch'),
  ]) {
    test('not remembering: a finished read (${outcome['phase']}) closes '
        'the page, which clears the sign-in', () async {
      final browser = BrowserFake()..remembered = false;
      final reader = await read(browser, outcome);
      expect(reader.phase, outcome['phase']);
      expect(reader.browserOpen, isFalse);
      // One close before opening, one after the read.
      expect(browser.closes, 2);
      reader.dispose();
    });
  }

  for (final phase in [
    'loginRequired',
    'awaitingIdentity',
    'emptyUnconfirmed',
  ]) {
    test('not remembering: stopping at $phase keeps the page open, so an '
        'emailed code is not asked for again', () async {
      final browser = BrowserFake()..remembered = false;
      final reader = await read(browser, result(phase));
      expect(reader.phase, phase);
      expect(reader.browserOpen, isTrue);
      expect(browser.closes, 1);
      reader.dispose();
    });
  }

  test('opening waits while the last page is still clearing', () async {
    final browser = BrowserFake()
      ..remembered = false
      ..busyOpens = 2;
    final reader = HangarReaderController(
      browser,
      PreviewFake(),
      pollInterval: Duration.zero,
    );
    await reader.open();
    expect(reader.phase, 'ready');
    expect(browser.opens, 3);
    reader.dispose();
  });

  test('a start-up clear that failed while opening waited is reported once '
      'the page opens', () async {
    final browser = BrowserFake()
      ..remembered = false
      ..busyOpens = 2
      ..unclearedOnOpen = true;
    final reader = HangarReaderController(
      browser,
      PreviewFake(),
      pollInterval: Duration.zero,
    );
    await reader.open();
    expect(reader.phase, 'ready');
    expect(reader.uncleared, isTrue);
    reader.dispose();
  });

  test('remembering: a finished read leaves the page open as before', () async {
    final browser = BrowserFake();
    final reader = await read(browser, {
      ...result('complete'),
      'canSave': true,
    });
    expect(reader.browserOpen, isTrue);
    expect(browser.closes, 1);
    reader.dispose();
  });

  test(
    'turning remembering off while the page is open clears and reopens',
    () async {
      final browser = BrowserFake();
      final reader = HangarReaderController(browser, PreviewFake());
      await reader.open();
      await reader.setRemember(false);
      expect(browser.choices, [false]);
      expect(browser.clears, 1);
      expect(reader.remember, isFalse);
      expect(browser.opens, 2);
      expect(reader.browserOpen, isTrue);
      expect(reader.phase, 'ready');
      reader.dispose();
    },
  );

  test('turning remembering on with no page open needs no reopen', () async {
    final browser = BrowserFake()..remembered = false;
    final reader = HangarReaderController(browser, PreviewFake());
    await reader.refreshSignIn();
    await reader.setRemember(true);
    expect(browser.choices, [true]);
    expect(browser.opens, 0);
    expect(reader.remember, isTrue);
    reader.dispose();
  });

  test('a choice that could not be saved changes nothing; the open page '
      'stays open and can still be closed', () async {
    final browser = BrowserFake()..choiceFailure = 'choice_failed';
    final reader = HangarReaderController(browser, PreviewFake());
    await reader.open();
    await reader.setRemember(false);
    expect(reader.remember, isTrue);
    expect(reader.phase, 'choice_failed');
    expect(reader.choiceError, 'choice_failed');
    expect(reader.browserOpen, isTrue);
    await reader.cancel();
    expect(browser.closes, 2);
    reader.dispose();
  });

  test(
    'reopening reports a clear that failed while closing the last page',
    () async {
      final browser = BrowserFake()..remembered = false;
      final reader = HangarReaderController(browser, PreviewFake());
      await reader.open();
      expect(reader.uncleared, isFalse);
      browser.closeLeavesUncleared = true;
      await reader.open();
      expect(reader.uncleared, isTrue);
      reader.dispose();
    },
  );

  test('a clear that did not finish is reported, not assumed done', () async {
    final browser = BrowserFake()
      ..remembered = false
      ..uncleared = true;
    final reader = HangarReaderController(browser, PreviewFake());
    await reader.open();
    expect(reader.uncleared, isTrue);
    browser.uncleared = false;
    await reader.cancel();
    expect(reader.uncleared, isFalse);
    reader.dispose();
  });

  test('finished results stay on screen when the choice changes', () async {
    final browser = BrowserFake();
    final reader = await read(browser, {
      ...result('complete'),
      'canSave': true,
    });
    await reader.setRemember(false);
    expect(reader.phase, 'complete');
    expect(reader.remember, isFalse);
    expect(browser.opens, 1);
    reader.dispose();
  });

  group('reader page', () {
    Future<void> enter(WidgetTester tester, BrowserFake browser) async {
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
    }

    testWidgets('shows the choice, unticked by default, with no clear button', (
      tester,
    ) async {
      final browser = BrowserFake()..remembered = false;
      await enter(tester, browser);
      expect(find.text('在这台电脑上记住 RSI 登录'), findsOneWidget);
      expect(find.textContaining('不记住的话，读完会自动清除，下次要重新登录。'), findsOneWidget);
      expect(find.textContaining('更改后网页会重新打开，需要重新登录一次。'), findsOneWidget);
      final tile = tester.widget<StarBridgeCheckboxTile>(
        find.byType(StarBridgeCheckboxTile),
      );
      expect(tile.value, isFalse);
      expect(control('hangar-reader-clear'), findsNothing);
    });

    testWidgets('ticking it remembers, reopens the page and shows the clear '
        'button', (tester) async {
      final browser = BrowserFake()..remembered = false;
      await enter(tester, browser);
      await tester.tap(find.text('在这台电脑上记住 RSI 登录'));
      await tester.pumpAndSettle();
      expect(browser.choices, [true]);
      expect(browser.opens, 2);
      expect(control('hangar-reader-clear'), findsOneWidget);
      expect(find.textContaining('登录状态保留在本机；过期时需重新登录。'), findsOneWidget);
    });

    testWidgets('a choice that could not be read is said plainly: nothing '
        'clears by itself, and the manual clear stays within reach', (
      tester,
    ) async {
      final browser = BrowserFake()
        ..remembered = false
        ..unknown = true;
      await enter(tester, browser);
      expect(find.textContaining('没能读取“记住 RSI 登录”这个设置'), findsOneWidget);
      expect(find.textContaining('不记住的话，读完会自动清除'), findsNothing);
      expect(control('hangar-reader-clear'), findsOneWidget);
    });

    testWidgets('a clear that did not finish is said plainly and the manual '
        'clear stays within reach', (tester) async {
      final browser = BrowserFake()
        ..remembered = false
        ..uncleared = true;
      await enter(tester, browser);
      expect(find.textContaining('上次没能清除 RSI 登录数据'), findsOneWidget);
      expect(control('hangar-reader-clear'), findsOneWidget);
    });
  });
}
