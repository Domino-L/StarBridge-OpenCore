import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_copy.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_waiting.dart';
import 'package:starbridge_flutter/shared/guide/guide_controller.dart';
import 'package:starbridge_flutter/shared/guide/guide_scope.dart';
import 'package:starbridge_flutter/shared/guide/guide_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_state_adapters.dart';

import 'hangar_reader_test.dart' show BrowserFake, PreviewFake;

const clearSuccess = '已退出 RSI 登录，并清除了本机保存的 RSI 登录数据。下次读取机库时需要重新登录 RSI。';

class ClearBrowser extends BrowserFake {
  Completer<void>? pendingClear;
  @override
  Future<void> clearData() async {
    await super.clearData();
    await pendingClear?.future;
  }
}

/// Real reader inside the shell's nested Navigator; dialogs use the root.
/// No native browser, transport, persisted profile or real account is used.
class HangarClearRig {
  final browser = ClearBrowser();
  final account = createAccountModule(
    InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
  );
  final guide = GuideController(
    InMemoryGuideState(const GuideState(available: true, eligible: true)),
  );
  final online = ValueNotifier(true);
  late final hub = GuideHub(
    controller: guide,
    online: online,
    navigate: (_) {},
  );

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    double ratio = 1,
    bool nested = true,
    Locale locale = const Locale('zh', 'CN'),
    GlobalKey? captureKey,
  }) async {
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = size * ratio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await account.initialize();
    await guide.refresh();
    final page = Scaffold(
      body: HangarPage(
        account: account,
        previewFactory: PreviewFake.new,
        browserFactory: () => browser,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            locale,
          ),
          builder: (_, child) => GuideScope(hub: hub, child: child!),
          home: nested
              ? Navigator(
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: (_) => page),
                )
              : page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hangar-open-reader')));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    hub.dispose();
    guide.dispose();
    account.dispose();
    online.dispose();
  }
}

Future<void> openClear(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('hangar-reader-clear')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('hangar-clear-confirm')), findsOneWidget);
}

void main() {
  for (final nested in [false, true]) {
    for (final step in [0, 1, 2, 3, 4, 5]) {
      testWidgets('clear works during guide step $step nested=$nested', (
        tester,
      ) async {
        final rig = HangarClearRig();
        await rig.pump(tester, nested: nested);
        rig.hub.start('hangar', at: step);
        await tester.pumpAndSettle();
        if (step == 3) {
          // The clear exception must not make the rest of this waiting step
          // interactive. Back is still outside its permitted hit regions.
          await tester.tapAt(
            tester.getCenter(find.byKey(const Key('hangar-reader-back'))),
          );
          await tester.pumpAndSettle();
          expect(rig.hub.run.value?.index, step);
        }
        expect(rig.browser.shown, isTrue);
        await openClear(tester);
        expect(
          rig.browser.shown,
          isFalse,
          reason: 'A root dialog must hide a nested native viewport',
        );
        expect(find.byKey(const Key('guide-tour-card')), findsNothing);
        expect(rig.browser.clears, 0);
        await tester.tap(find.byKey(const Key('hangar-clear-cancel')));
        await tester.pumpAndSettle();
        expect(rig.browser.shown, isTrue);
        expect(rig.browser.clears, 0);
        expect(tester.takeException(), isNull);
        await rig.dispose(tester);
      });
    }
  }

  testWidgets('pending clear is visible, locked and has an explicit receipt', (
    tester,
  ) async {
    final rig = HangarClearRig();
    final pending = Completer<void>();
    rig.browser.pendingClear = pending;
    await rig.pump(tester);
    await openClear(tester);
    await tester.tap(find.byKey(const Key('hangar-clear-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('正在退出并清除…'), findsNWidgets(2));
    final button = tester.widget<StarBridgeActionButton>(
      find
          .ancestor(
            of: find.byKey(const Key('hangar-reader-clear')),
            matching: find.byType(StarBridgeActionButton),
          )
          .first,
    );
    expect(button.onActivate, isNull);
    expect(rig.browser.clears, 1);
    expect(rig.browser.shown, isFalse);
    expect(find.byKey(const Key('hangar-reader-cancel')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('hangar-reader-progress')),
        matching: find.byType(HangarReaderWaiting),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 14));
    expect(rig.browser.clears, 1);
    expect(find.text('正在退出并清除…'), findsNWidgets(2));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text(clearSuccess), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
    expect(find.text('已退出并清除'), findsWidgets);
    await tester.tap(find.byKey(const Key('hangar-clear-result-ok')));
    await tester.pumpAndSettle();
    expect(find.text(clearSuccess), findsNothing);
    expect(find.text('已退出并清除'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await rig.dispose(tester);
  });

  for (final failure in ['clear_busy', 'clear_unsafe', 'clear_failed']) {
    testWidgets('$failure is explicit and can be retried', (tester) async {
      final rig = HangarClearRig();
      rig.browser.clearFailure = failure;
      await rig.pump(tester);
      await openClear(tester);
      await tester.tap(find.byKey(const Key('hangar-clear-confirm')));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(HangarPage));
      final message = HangarReaderCopy(context).status(failure);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(message),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('未能清除'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('退出 RSI 登录并清除数据'),
        ),
        findsNothing,
      );
      expect(find.text(clearSuccess), findsNothing);
      await tester.tap(find.byKey(const Key('hangar-clear-result-ok')));
      await tester.pumpAndSettle();
      rig.browser.clearFailure = null;
      await openClear(tester);
      await tester.tap(find.byKey(const Key('hangar-clear-confirm')));
      await tester.pumpAndSettle();
      expect(rig.browser.clears, 2);
      expect(find.text(clearSuccess), findsOneWidget);
      expect(tester.takeException(), isNull);
      await rig.dispose(tester);
    });
  }

  testWidgets('Escape restores the viewport without clearing', (tester) async {
    final rig = HangarClearRig();
    await rig.pump(tester);
    await openClear(tester);
    expect(rig.browser.shown, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(rig.browser.shown, isTrue);
    expect(rig.browser.clears, 0);
    await rig.dispose(tester);
  });

  testWidgets('leaving during clear never opens a stale result dialog', (
    tester,
  ) async {
    final rig = HangarClearRig();
    final pending = Completer<void>();
    rig.browser.pendingClear = pending;
    await rig.pump(tester);
    await openClear(tester);
    await tester.tap(find.byKey(const Key('hangar-clear-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('hangar-reader-back')));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('hangar-open-reader')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await rig.dispose(tester);
  });

  for (final (locale, message, ok) in [
    (const Locale('zh', 'CN'), clearSuccess, '知道了'),
    (
      const Locale('zh', 'TW'),
      '已登出 RSI，並清除了本機儲存的 RSI 登入資料。下次讀取機庫時需要重新登入 RSI。',
      '知道了',
    ),
    (
      const Locale('en', 'US'),
      "Signed out of RSI and cleared the RSI sign-in data saved on this device. You'll need to sign in to RSI again the next time you read your hangar.",
      'OK',
    ),
  ]) {
    testWidgets('clear failure title uses $locale copy', (tester) async {
      final rig = HangarClearRig();
      rig.browser.clearFailure = 'clear_busy';
      await rig.pump(tester, locale: locale);
      await openClear(tester);
      await tester.tap(find.byKey(const Key('hangar-clear-confirm')));
      await tester.pumpAndSettle();
      final title = switch (locale.countryCode) {
        'CN' || 'TW' => '未能清除',
        _ => "Couldn't clear",
      };
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(title),
        ),
        findsOneWidget,
      );
      expect(find.text(ok), findsOneWidget);
      expect(find.text(message), findsNothing);
      await rig.dispose(tester);
    });

    testWidgets('clear receipt uses $locale copy', (tester) async {
      final rig = HangarClearRig();
      await rig.pump(tester, locale: locale);
      await openClear(tester);
      await tester.tap(find.byKey(const Key('hangar-clear-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.text(ok), findsOneWidget);
      await rig.dispose(tester);
    });
  }
}
