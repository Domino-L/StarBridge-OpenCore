import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/legal/starbridge_third_party_licenses.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_browser.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_details.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_copy.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_route.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3dk_test.dart';
import 'interaction_batch3dj_test.dart' show visibleFrames, remove;
import 'interaction_batch3aa_test.dart' show reader;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts;

class LongEntry extends LicenseEntry {
  @override
  Iterable<String> get packages => ['App'];
  @override
  Iterable<LicenseParagraph> get paragraphs => [
    for (var i = 0; i < 60; i++) LicenseParagraph('Original paragraph $i', 0),
  ];
}

void main() {
  setUpAll(loadFonts);
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite keyboard wide automatic detail wait stays static, sheet starts at toolbar',
      (t) async {
        LicenseRegistry.addLicense(() async* {
          yield Entry(['App'], 'BODY');
        });
        await mount(t, suite, wide: true);
        final previous = t.binding.schedulingStrategy;
        t.binding.schedulingStrategy = ({
          required priority,
          required scheduler,
        }) => false;
        addTearDown(() => t.binding.schedulingStrategy = previous);
        await activate(t, 'open', keyboard: true);
        await visibleFrames(t);
        expect(find.byType(ThirdPartyLicenseDetails), findsOneWidget);
        expect(find.byType(HelpSupportWaiting), findsOneWidget);
        expect(find.byType(SuiteProgressBar), findsNothing);
        final title = find.byType(ThirdPartyLicenseTitle);
        expect(t.getTopLeft(title).dy, inInclusiveRange(56.0, 64.0));
        final card = find.ancestor(
          of: find.byType(ThirdPartyLicenseDetails),
          matching: find.byType(Card),
        );
        expect(t.getTopLeft(card).dy, closeTo(kToolbarHeight, 1));
        t.binding.schedulingStrategy = previous;
        while (t.binding.handleEventLoopCallback()) {}
        await settleRead(t);
        expect(find.text('BODY Heading'), findsOneWidget);
        expectInstantDetails(t);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite fast package selection does not decode stale queued body',
      (t) async {
        final a = Entry(['App'], 'A'),
            b = Entry(['Beta'], 'B'),
            c = Entry(['Gamma'], 'C');
        LicenseRegistry.addLicense(() async* {
          yield a;
          yield b;
          yield c;
        });
        await mount(t, suite, wide: true);
        await activate(t, 'open');
        await settleRead(t);
        final previous = t.binding.schedulingStrategy;
        t.binding.schedulingStrategy = ({
          required priority,
          required scheduler,
        }) => false;
        addTearDown(() => t.binding.schedulingStrategy = previous);
        await activate(t, 'license-package-Beta');
        await t.pump();
        await activate(t, 'license-package-Gamma');
        await t.pump();
        t.binding.schedulingStrategy = previous;
        while (t.binding.handleEventLoopCallback()) {}
        await settleRead(t);
        expect(b.reads, 0);
        expect(c.reads, 1);
        expect(find.text('B Heading'), findsNothing);
        expect(find.text('C Heading'), findsOneWidget);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite narrow system back restores directory and focused row; hidden rows not actionable',
      (t) async {
        LicenseRegistry.addLicense(() async* {
          yield Entry(['App', 'Other'], 'BODY');
        });
        await mount(t, suite);
        final semantics = t.ensureSemantics();
        await activate(t, 'open', keyboard: true);
        await settleRead(t);
        reader(t, 'Other\n1 份许可');
        await settleRead(t);
        expect(find.byType(ThirdPartyLicenseDetails), findsOneWidget);
        expect(
          exposedNodes(t)
              .where((n) => n.getSemanticsData().label == 'App\n1 份许可'),
          isEmpty,
        );
        await t.binding.handlePopRoute();
        await visibleFrames(t);
        expect(find.byType(ThirdPartyLicenseDetails), findsNothing);
        expect(find.byType(ThirdPartyLicenseBrowser), findsOneWidget);
        final pressable = t.widget<SuitePressable>(
          find.byKey(const Key('license-package-Other')),
        );
        expect(pressable.focusNode!.hasFocus, isTrue);
        await t.binding.handlePopRoute();
        await visibleFrames(t);
        expect(find.byType(ThirdPartyLicenseBrowser), findsNothing);
        await remove(t);
        semantics.dispose();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite empty registry preserves app attribution and never offers a fake retry',
      (t) async {
        await mount(t, suite, wide: true);
        await activate(t, 'open');
        await settleRead(t);
        expect(find.text('Powered by Flutter'), findsOneWidget);
        expect(find.byType(ThirdPartyLicenseDetails), findsNothing);
        expect(find.byType(HelpSupportWaiting), findsNothing);
        expect(find.byKey(const Key('license-directory-retry')), findsNothing);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite list scroll survives detail and back; document has complete long text',
      (t) async {
        var collects = 0;
        LicenseRegistry.addLicense(() async* {
          collects++;
          yield LongEntry();
          for (var i = 0; i < 50; i++) {
            yield Entry(['Package${i.toString().padLeft(2, '0')}'], 'P$i');
          }
        });
        await mount(t, suite);
        await activate(t, 'open');
        await settleRead(t);
        final list = find.byKey(const PageStorageKey('license-directory'));
        await t.drag(list, const Offset(0, -1000));
        await t.pumpAndSettle();
        final before = t.widget<ListView>(list).controller!.offset;
        expect(before, greaterThan(0));
        final candidates = find
            .byType(SuitePressable)
            .evaluate()
            .where((e) => e.widget.key.toString().contains('license-package'))
            .toList();
        final target = candidates.firstWhere(
          (e) =>
              t.getRect(find.byWidget(e.widget)).center.dy > 100 &&
              t.getRect(find.byWidget(e.widget)).center.dy < 800,
        );
        await t.tap(find.byWidget(target.widget));
        await settleRead(t);
        await activate(t, 'license-back');
        await settleRead(t);
        expect(t.widget<ListView>(list).controller!.offset, closeTo(before, 1));
        t.widget<ListView>(list).controller!.jumpTo(0);
        await visibleFrames(t);
        await activate(t, 'license-package-App');
        await settleRead(t);
        final detailList = find.descendant(
          of: find.byType(ThirdPartyLicenseDetails),
          matching: find.byType(ListView),
        );
        await t.scrollUntilVisible(
          find.text('Original paragraph 59'),
          400,
          scrollable: find
              .descendant(of: detailList, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 20,
        );
        await t.pumpAndSettle();
        expect(find.text('Original paragraph 59'), findsOneWidget);
        expect(collects, 1);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'show keeps nearest Navigator, captured local theme and registration owner',
    (t) async {
      var collects = 0;
      LicenseRegistry.addLicense(() async* {
        collects++;
        yield Entry(['App'], 'BODY');
      });
      final outer = GlobalKey<NavigatorState>(),
          inner = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: outer,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          locale: const Locale('en', 'US'),
          supportedLocales: AppStrings.supportedLocales,
          home: Navigator(
            key: inner,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Theme(
                data: ThemeData.dark().copyWith(
                  cardColor: const Color(0xff123456),
                ),
                child: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () =>
                          StarBridgeThirdPartyLicenses.show(context),
                      child: const Text('Open nested'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open nested'));
      await settleRead(t);
      expect(inner.currentState!.canPop(), isTrue);
      expect(outer.currentState!.canPop(), isFalse);
      final element = t.element(find.byType(ThirdPartyLicenseBrowser));
      expect(Theme.of(element).cardColor, const Color(0xff123456));
      expect(ModalRoute.of(element), isA<StarBridgePageRoute<void>>());
      expect(collects, 1);
      await remove(t);
      expect(t.takeException(), isNull);
    },
  );

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets(
      'status copy is localized without changing license body $locale',
      (t) async {
        late ({String loading, String failed, String retry}) copy;
        await t.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) {
                copy = thirdPartyLicenseCopy(context);
                return Text(copy.loading);
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(copy.loading, isNotEmpty);
        expect(copy.failed, isNotEmpty);
        expect(
          copy.retry,
          locale.languageCode == 'en'
              ? 'Try again'
              : locale.countryCode == 'TW'
              ? '重試'
              : '重试',
        );
        await remove(t);
      },
    );
  }
}
