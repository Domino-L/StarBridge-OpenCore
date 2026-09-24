import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/hangar_browser_viewport.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_controller.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_port.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

void main() {
  test('saveable scan stays available until the user leaves or cancels', () async {
    final preview = PreviewFake()
      ..results = [{...result('complete'), 'canSave': true}];
    final reader = HangarReaderController(BrowserFake(), preview);
    await reader.open();
    final before = preview.cancels;
    await reader.read();
    expect(reader.phase, 'complete');
    expect(preview.cancels, before,
        reason: 'Finishing a scan must not discard the pending local save');
    await reader.cancel();
    expect(preview.cancels, before + 1);
    reader.dispose();
  });
  if (const bool.fromEnvironment('HANGAR_READER_GOLDENS')) {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() async {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
        'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    });
  }
  test('reader does not open a browser or start reading implicitly', () async {
    final browser = BrowserFake();
    final preview = PreviewFake();
    final reader = HangarReaderController(browser, preview);
    expect(reader.phase, 'idle');
    expect(browser.opens, 0);
    expect(preview.begins, 0);
    await reader.open();
    expect(reader.phase, 'ready');
    expect(preview.begins, 0);
    reader.dispose();
  });
  test('Host result controls sequential pages and local preview', () async {
    final browser = BrowserFake();
    final preview = PreviewFake()
      ..results = [
        result('reading', page: 2),
        result('verifying'),
        result('complete'),
      ];
    final reader = HangarReaderController(
      browser,
      preview,
      pollInterval: Duration.zero,
    );
    await reader.open();
    await reader.read();
    expect(browser.pages, [1, 2, 1]);
    expect(reader.phase, 'complete');
    expect(reader.view['canSave'], false);
    expect(preview.verifications, 1);
    expect(browser.events, [
      'lock',
      'page:1',
      'capture',
      'page:2',
      'capture',
      'page:1',
      'capture',
      'unlock',
    ]);
    expect(browser.locked, false);
    reader.dispose();
  });
  test('cancelled capture cannot revive result or navigate', () async {
    final pending = Completer<Map<String, Object?>>();
    final browser = BrowserFake()..pendingCapture = pending;
    final preview = PreviewFake();
    final reader = HangarReaderController(browser, preview);
    await reader.open();
    final reading = reader.read();
    await Future<void>.delayed(Duration.zero);
    await reader.cancel();
    expect(reader.phase, 'cancelled');
    expect(reader.browserOpen, false);
    await reader.open();
    expect(
      browser.opens,
      1,
      reason: 'Old asynchronous operation must drain before retry',
    );
    pending.complete({});
    await reading;
    expect(preview.observations, 0);
    expect(reader.phase, 'cancelled');
    browser.pendingCapture = null;
    await reader.open();
    expect(browser.opens, 2);
    reader.dispose();
  });
  test(
    'cancellation while account checking never starts page navigation',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final preview = PreviewFake()..pendingBegin = pending;
      final browser = BrowserFake();
      final reader = HangarReaderController(browser, preview);
      await reader.open();
      final reading = reader.read();
      await reader.cancel();
      pending.complete(result('ready'));
      await reading;
      expect(reader.phase, 'cancelled');
      expect(browser.pages, isEmpty);
      reader.dispose();
    },
  );
  test(
    'missing Handle unlocks and a retry starts a fresh identity check',
    () async {
      final preview = PreviewFake()
        ..results = [result('awaitingIdentity'), result('complete')];
      final browser = BrowserFake();
      final reader = HangarReaderController(browser, preview);
      await reader.open();
      await reader.read();
      expect(reader.paused, true);
      await reader.read();
      expect(preview.begins, 2);
      expect(preview.verifications, 2);
      expect(browser.locked, false);
      expect(browser.pages, [1]);
      expect(reader.phase, 'complete');
      reader.dispose();
    },
  );
  test('slow page is retried, perpetual loading has finite timeout', () async {
    final browser = BrowserFake()..loadingCount = 2;
    final preview = PreviewFake();
    final reader = HangarReaderController(
      browser,
      preview,
      pollInterval: const Duration(milliseconds: 1),
      pageTimeout: const Duration(milliseconds: 30),
    );
    await reader.open();
    await reader.read();
    expect(reader.phase, 'complete');
    browser.loadingCount = 10000;
    await reader.read();
    expect(reader.phase, 'timedOut');
    expect(browser.locked, false);
    reader.dispose();
  });
  test('account switch drops visible results and closes browser', () async {
    final browser = BrowserFake();
    final reader = HangarReaderController(browser, PreviewFake());
    await reader.open();
    await reader.read();
    await reader.cancel(reason: 'accountChanged');
    expect(reader.view, isEmpty);
    expect(reader.browserOpen, false);
    reader.dispose();
  });
  test(
    'late initial identity verification cannot restore a cancelled account',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final browser = BrowserFake();
      final preview = PreviewFake()..pendingVerify = pending;
      final reader = HangarReaderController(browser, preview);
      await reader.open();
      final reading = reader.read();
      await Future<void>.delayed(Duration.zero);
      expect(browser.locked, true);
      expect(browser.pages, isEmpty);
      await reader.cancel(reason: 'accountChanged');
      pending.complete(result('reading'));
      await reading;
      expect(reader.view, isEmpty);
      expect(reader.phase, 'accountChanged');
      expect(browser.locked, false);
      expect(browser.pages, isEmpty);
      reader.dispose();
    },
  );
  test(
    'reopening reuses the same account profile without reusing a scan',
    () async {
      final browser = BrowserFake();
      final reader = HangarReaderController(browser, PreviewFake());
      await reader.open();
      await reader.read();
      await reader.open();
      expect(browser.profileKeys, ['A' * 64, 'A' * 64]);
      expect(browser.locked, false);
      expect(reader.view, isEmpty);
      reader.dispose();
    },
  );
  test('missing Runtime can retry without an independent window', () async {
    final browser = BrowserFake()..failOpen = true;
    final reader = HangarReaderController(browser, PreviewFake());
    await reader.open();
    expect(reader.phase, 'runtime');
    browser.failOpen = false;
    await reader.open();
    expect(reader.phase, 'ready');
    reader.dispose();
  });
  testWidgets('in-app flow exposes cancellation and preview without save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1050, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    await account.initialize();
    final browser = BrowserFake();
    final preview = PreviewFake();
    await tester.pumpWidget(
      app(
        HangarPage(
          account: account,
          previewFactory: () => preview,
          browserFactory: () => browser,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('hangar-open-reader')));
    await tester.pumpAndSettle();
    expect(find.text('打开 RSI 机库'), findsNothing);
    expect(browser.opens, 1);
    if (const bool.fromEnvironment('HANGAR_READER_GOLDENS')) {
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../../../../.artifacts/hangar-reader-ui/reader-entry.png',
        ),
      );
    }
    expect(find.byKey(const Key('hangar-browser-viewport')), findsOneWidget);
    expect(browser.shown, true);
    final pending = Completer<Map<String, Object?>>();
    browser.pendingCapture = pending;
    await tester.tap(find.byKey(const Key('hangar-reader-action')));
    await tester.pump();
    expect(find.byKey(const Key('hangar-reader-cancel')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(browser.locked, true);
    expect(
      tester
          .widget<HangarBrowserViewport>(find.byType(HangarBrowserViewport))
          .interactive,
      false,
    );
    pending.complete({});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-reader-preview')), findsOneWidget);
    expect(find.textContaining('尚未保存'), findsOneWidget);
    expect(find.text('Test Ship'), findsOneWidget);
    expect(browser.shown, false);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('HANGAR_READER_GOLDENS')) {
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../../../../.artifacts/hangar-reader-ui/reader-preview.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox());
    account.dispose();
  });
  testWidgets(
    'verified ships appear beside the browser before scanning finishes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final nextPage = Completer<Map<String, Object?>>();
      final browser = BrowserFake()..captureQueue = [null, nextPage];
      final preview = PreviewFake()
        ..results = [
          {
            ...result('reading', page: 2),
            'shipCount': 18,
            'ships': List.generate(
              18,
              (index) => {
                'title': index == 0 ? 'Test Ship' : '示例舰船 ${index + 1}',
                'liner': 'Test Builder',
              },
            ),
          },
          result('complete'),
        ];
      await tester.pumpWidget(
        app(
          HangarPage(
            account: account,
            previewFactory: () => preview,
            browserFactory: () => browser,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('hangar-open-reader')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-reader-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Test Ship'), findsOneWidget);
      for (final text in ['已识别舰船', 'Test Ship']) {
        expect(
          tester.widget<Text>(find.text(text)).style?.fontFamilyFallback,
          contains('Source Han Sans CN'),
        );
      }
      expect(find.byKey(const Key('hangar-reader-cancel')), findsOneWidget);
      final web = tester.getRect(
        find.byKey(const Key('hangar-browser-viewport')),
      );
      final results = tester.getRect(
        find.byKey(const Key('hangar-reader-live-results')),
      );
      expect(web.overlaps(results), false);
      expect(results.left, greaterThan(web.right));
      expect(results.width, greaterThanOrEqualTo(280));
      expect(browser.shown, true);
      if (const bool.fromEnvironment('HANGAR_READER_GOLDENS')) {
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../../../../.artifacts/hangar-reader-ui/reader-live.png',
          ),
        );
      }
      nextPage.complete({});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hangar-reader-preview')), findsOneWidget);
      expect(browser.shown, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    },
  );
  for (final error in {
    'identityReadFailed': '暂时无法读取网页账号信息。请重新打开机库后重试。',
    'identityAmbiguous': '网页中的账号信息不一致。请重新打开机库后重试。',
    'identityMismatch': '网页账号与应用内 Handle 不一致。请登录对应的 RSI 账号后重试。',
  }.entries) {
    testWidgets('${error.key} has its own explanation and retry action', (
      tester,
    ) async {
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final preview = PreviewFake()..results = [result(error.key)];
      await tester.pumpWidget(
        app(
          HangarPage(
            account: account,
            previewFactory: () => preview,
            browserFactory: BrowserFake.new,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('hangar-open-reader')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-reader-action')));
      await tester.pumpAndSettle();
      expect(find.text(error.value), findsOneWidget);
      expect(find.text('重新打开'), findsOneWidget);
      if (error.key != 'identityMismatch') {
        expect(find.textContaining('网页账号与应用内 Handle 不一致'), findsNothing);
      }
      expect(find.byKey(const Key('hangar-reader-preview')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    });
  }
  for (final size in [const Size(780, 550), const Size(1800, 950)]) {
    testWidgets('reader layout uses viewport at $size without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final browser = BrowserFake();
      await tester.pumpWidget(
        app(
          HangarPage(
            account: account,
            previewFactory: PreviewFake.new,
            browserFactory: () => browser,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('hangar-open-reader')));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(HangarBrowserViewport));
      final results = tester.getRect(
        find.byKey(const Key('hangar-reader-live-results')),
      );
      final ratio = MediaQuery.devicePixelRatioOf(
        tester.element(find.byType(HangarBrowserViewport)),
      );
      expect(browser.rect.width / ratio, closeTo(viewport.width, .1));
      expect(browser.rect.height / ratio, closeTo(viewport.height, .1));
      expect(viewport.overlaps(results), false);
      if (size.width >= 948) {
        expect(results.left, greaterThan(viewport.right));
        expect(viewport.width, greaterThan(600));
      } else {
        expect(results.top, greaterThan(viewport.bottom));
        expect(viewport.width, greaterThan(size.width - 70));
      }
      expect(viewport.height, greaterThan(140));
      expect(tester.takeException(), isNull);
      if (size.width < 948 &&
          const bool.fromEnvironment('HANGAR_READER_GOLDENS')) {
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../../../../.artifacts/hangar-reader-ui/reader-compact.png',
          ),
        );
      }
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    });
  }
  testWidgets(
    'menu opens hide viewport and disposal releases visibility gate',
    (tester) async {
      final browser = BrowserFake();
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final showMenu = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        app(
          Column(
            children: [
              ValueListenableBuilder(
                valueListenable: showMenu,
                builder: (_, show, _) => show
                    ? NativeViewportMenu(
                        builder: (open, close) => MenuAnchor(
                          onOpen: open,
                          onClose: close,
                          menuChildren: const [
                            MenuItemButton(child: Text('Entry')),
                          ],
                          builder: (_, controller, _) => TextButton(
                            onPressed: controller.open,
                            child: const Text('Menu'),
                          ),
                        ),
                      )
                    : const SizedBox(),
              ),
              Expanded(
                child: HangarPage(
                  account: account,
                  previewFactory: PreviewFake.new,
                  browserFactory: () => browser,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('hangar-open-reader')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(browser.shown, false);
      showMenu.value = false;
      await tester.pumpAndSettle();
      expect(nativeViewportMenus.value, 0);
      expect(browser.shown, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      showMenu.dispose();
    },
  );
}

Widget app(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  ),
  home: Scaffold(body: child),
);

Map<String, Object?> result(String phase, {int page = 1}) => {
  'schemaVersion': 1,
  'operationId': 'synthetic-operation',
  'phase': phase,
  'expectedPage': page,
  'totalPages': 2,
  'pagesRead': phase == 'complete' ? 2 : 1,
  'shipCount': 1,
  'unclassifiedCount': 0,
  'canSave': false,
  'ships': [
    {'title': 'Test Ship', 'liner': 'Test Builder'},
  ],
};

class PreviewFake implements HangarPreviewPort {
  int begins = 0, observations = 0, cancels = 0, verifications = 0;
  List<Map<String, Object?>> results = [];
  Completer<Map<String, Object?>>? pendingBegin;
  Completer<Map<String, Object?>>? pendingVerify;
  @override
  Future<String> prepare() async => 'A' * 64;
  @override
  Future<Map<String, Object?>> verify(Map<String, Object?> observation) async {
    verifications++;
    if (pendingVerify != null) return pendingVerify!.future;
    if (results.isNotEmpty &&
        [
          'awaitingIdentity',
          'identityReadFailed',
          'identityAmbiguous',
          'identityMismatch',
        ].contains(results.first['phase'])) {
      return results.removeAt(0);
    }
    return result('reading');
  }

  @override
  Future<Map<String, Object?>> begin() async {
    begins++;
    return pendingBegin?.future ?? result('ready');
  }

  @override
  Future<Map<String, Object?>> observe(Map<String, Object?> observation) async {
    observations++;
    return results.isEmpty ? result('complete') : results.removeAt(0);
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

class BrowserFake implements HangarBrowserPort {
  @override
  void setFocusExitHandler(void Function(bool previous)? handler) {}
  int opens = 0, closes = 0, loadingCount = 0;
  bool failOpen = false, shown = false;
  bool locked = false;
  List<String> events = [];
  List<String> profileKeys = [];
  Rect rect = Rect.zero;
  List<int> pages = [];
  Completer<Map<String, Object?>>? pendingCapture;
  List<Completer<Map<String, Object?>>?> captureQueue = [];
  @override
  Future<void> open({required String profileKey}) async {
    opens++;
    profileKeys.add(profileKey);
    if (failOpen) throw const HangarReaderFailure('runtime');
  }

  @override
  Future<Map<String, Object?>> lock() async {
    locked = true;
    events.add('lock');
    return {};
  }

  @override
  Future<void> unlock() async {
    locked = false;
    events.add('unlock');
  }

  @override
  Future<void> page(int page) async {
    expect(locked, true);
    events.add('page:$page');
    pages.add(page);
  }

  @override
  Future<Map<String, Object?>> capture() async {
    expect(locked, true);
    events.add('capture');
    if (loadingCount-- > 0) throw const HangarReaderFailure('loading');
    if (captureQueue.isNotEmpty) return captureQueue.removeAt(0)?.future ?? {};
    return pendingCapture?.future ?? {};
  }

  @override
  Future<void> bounds(Rect rect, {required bool visible}) async {
    this.rect = rect;
    shown = visible;
  }

  @override
  Future<void> focus() async {}
  @override
  Future<void> close() async {
    closes++;
    locked = false;
    shown = false;
  }
}
