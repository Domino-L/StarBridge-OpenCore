import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/legal/starbridge_third_party_licenses.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_browser.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_details.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dj_test.dart' show visibleFrames, remove;
import 'interaction_batch3aa_test.dart' show reader;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

Future<void> activate(
  WidgetTester t,
  String key, {
  bool keyboard = false,
}) async {
  final target = find.byKey(Key(key));
  if (!keyboard) {
    await t.tap(target);
    return;
  }
  final node = switch (t.widget(target)) {
    ButtonStyleButton button => button.focusNode!,
    IconButton button => button.focusNode!,
    SuitePressable button => button.focusNode!,
    _ => throw StateError('No focus owner at $key'),
  };
  node.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

void expectInstantDetails(WidgetTester t) {
  final transition = find.descendant(
    of: find.byType(ThirdPartyLicenseBrowser),
    matching: find.byType(StarBridgePageTransition),
  );
  expect(transition, findsOneWidget);
  final widget = t.widget<StarBridgePageTransition>(transition);
  expect(widget.instant, isTrue);
  expect(widget.animation.value, 1);
  expect(widget.animation.isAnimating, isFalse);
  expect(find.byType(SuiteProgressBar), findsNothing);
}

class Entry extends LicenseEntry {
  Entry(this.names, this.body);
  final List<String> names;
  final String body;
  int reads = 0;
  bool fail = false;
  @override
  Iterable<String> get packages => names;
  @override
  Iterable<LicenseParagraph> get paragraphs {
    reads++;
    if (fail) throw StateError('private-paragraph-error');
    return [
      LicenseParagraph('$body Heading', LicenseParagraph.centeredIndent),
      LicenseParagraph('$body exact original\nwith line break', 2),
    ];
  }
}

class Host extends StatefulWidget {
  const Host(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  bool reduce = false, light = false;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    Builder(
      builder: (context) => Center(
        child: HelpSupportAction(
          controlKey: const Key('open'),
          onActivate: (_) => StarBridgeThirdPartyLicenses.show(context),
          child: const Text('Open'),
        ),
      ),
    ),
    widget.suite,
    reduce: reduce,
    light: light,
  );
}

Future<HostState> mount(
  WidgetTester t,
  InteractionSuite suite, {
  bool wide = false,
}) async {
  size(t, Size(wide ? 1280 : 700, 900));
  final key = GlobalKey<HostState>();
  await t.pumpWidget(Host(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

Future<void> settleRead(WidgetTester t) async {
  // scheduleTask parses at animation priority in the real event loop.
  for (var n = 0; n < 6; n++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadFonts);
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  for (final suite in InteractionSuite.values) {
    testWidgets('$suite directory, exact lazy paragraphs, back and reopen', (
      t,
    ) async {
      final first = Entry(['ZApp'], 'APP');
      final shared = Entry(['Beta', 'Alpha', 'Alpha'], 'SHARED');
      var collects = 0;
      LicenseRegistry.addLicense(() async* {
        collects++;
        yield first;
        yield shared;
      });
      await mount(t, suite);
      await activate(t, 'open');
      await settleRead(t);
      expect(find.byType(ThirdPartyLicenseBrowser), findsOneWidget);
      expect(collects, 1);
      expect(first.reads + shared.reads, 0);
      expect(find.text('Powered by Flutter'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('ZApp')).dy,
        lessThan(t.getTopLeft(find.text('Alpha')).dy),
      );
      await activate(t, 'license-package-Alpha');
      await settleRead(t);
      expect(first.reads, 0);
      expect(shared.reads, 2); // duplicate bindings are intentionally retained.
      expect(
        find.text('SHARED exact original\nwith line break'),
        findsNWidgets(2),
      );
      final heading = t.widget<Text>(find.text('SHARED Heading').first);
      expect(heading.textAlign, TextAlign.center);
      expect(heading.style!.fontWeight, FontWeight.bold);
      final paragraph = find
          .text('SHARED exact original\nwith line break')
          .first;
      final padding = t.widget<Padding>(
        find.ancestor(of: paragraph, matching: find.byType(Padding)).first,
      );
      expect(
        padding.padding,
        const EdgeInsetsDirectional.only(top: 8, start: 32),
      );
      expect(
        Localizations.localeOf(t.element(paragraph)),
        const Locale('en', 'US'),
      );
      expect(find.byKey(const Key('license-package-Beta')), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await visibleFrames(t);
      expect(find.byKey(const Key('license-package-Beta')), findsOneWidget);
      expect(find.byType(ThirdPartyLicenseDetails), findsNothing);
      expect(collects, 1);
      await activate(t, 'license-back');
      await t.pumpAndSettle();
      expect(find.byType(ThirdPartyLicenseBrowser), findsNothing);
      await activate(t, 'open');
      await settleRead(t);
      expect(collects, 2);
      await remove(t);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      '$suite wide first selection, same package does not decode again, resize keeps choice',
      (t) async {
        final first = Entry(['App'], 'APP');
        final other = Entry(['Other'], 'OTHER');
        var collects = 0;
        LicenseRegistry.addLicense(() async* {
          collects++;
          yield first;
          yield other;
        });
        await mount(t, suite, wide: true);
        await activate(t, 'open');
        await settleRead(t);
        expect(first.reads, 1);
        expect(other.reads, 0);
        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        await activate(t, 'license-package-App');
        await settleRead(t);
        expect(first.reads, 1);
        await activate(t, 'license-package-Other');
        await settleRead(t);
        expect(other.reads, 1);
        expect(find.text('OTHER Heading'), findsOneWidget);
        final custom = t.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        expect(custom.controller, isNotNull);
        expect(custom.controller!.hasClients, isTrue);
        t.view.physicalSize = const Size(700, 900);
        await settleRead(t);
        expect(find.text('OTHER Heading'), findsOneWidget);
        expect(find.byKey(const Key('license-package-App')), findsNothing);
        expect(collects, 1);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await visibleFrames(t);
        t.view.physicalSize = const Size(1280, 900);
        await settleRead(t);
        expect(find.text('OTHER Heading'), findsOneWidget);
        expect(collects, 1);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source waiting, completion, source and live reduce',
        (t) async {
          final gate = Completer<void>();
          var collects = 0;
          final entry = Entry(['App'], 'BODY');
          LicenseRegistry.addLicense(() async* {
            collects++;
            await gate.future;
            yield entry;
          });
          final host = await mount(t, suite);
          final semantics = t.ensureSemantics();
          if (source == 'reader') {
            reader(t, 'Open');
          } else {
            await activate(t, 'open', keyboard: source == 'keyboard');
          }
          await visibleFrames(t);
          expect(collects, 1);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(
            find.byType(SuiteProgressBar),
            source == 'pointer' ? findsOneWidget : findsNothing,
          );
          if (source != 'pointer') expect(t.hasRunningAnimations, isFalse);
          host.change(() {
            host.reduce = true;
            host.light = true;
          });
          await visibleFrames(t);
          expect(find.byType(SuiteProgressBar), findsNothing);
          expect(t.hasRunningAnimations, isFalse);
          gate.complete();
          await settleRead(t);
          await activate(t, 'license-package-App', keyboard: true);
          await settleRead(t);
          expect(find.text('BODY Heading'), findsOneWidget);
          expectInstantDetails(t);
          expect(entry.reads, 1);
          await remove(t);
          semantics.dispose();
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite failed directory retries once and never exposes partial registry or raw error',
      (t) async {
        var collects = 0;
        LicenseRegistry.addLicense(() async* {
          collects++;
          yield Entry(['Partial'], 'PARTIAL');
          if (collects == 1) throw StateError('secret-registry-error');
        });
        await mount(t, suite);
        await activate(t, 'open');
        await settleRead(t);
        expect(
          find.byKey(const Key('license-directory-retry')),
          findsOneWidget,
        );
        expect(find.textContaining('secret-registry-error'), findsNothing);
        expect(find.byKey(const Key('license-package-Partial')), findsNothing);
        expect(collects, 1);
        await activate(t, 'license-directory-retry', keyboard: true);
        await settleRead(t);
        expect(collects, 2);
        expect(
          find.byKey(const Key('license-package-Partial')),
          findsOneWidget,
        );
        expect(t.hasRunningAnimations, isFalse);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite failed paragraph retries same exact entry without registry reload',
      (t) async {
        final entry = Entry(['App'], 'BODY')..fail = true;
        var collects = 0;
        LicenseRegistry.addLicense(() async* {
          collects++;
          yield entry;
        });
        await mount(t, suite);
        await activate(t, 'open');
        await settleRead(t);
        await activate(t, 'license-package-App');
        await settleRead(t);
        expect(find.byKey(const Key('license-detail-retry')), findsOneWidget);
        expect(find.textContaining('private-paragraph-error'), findsNothing);
        entry.fail = false;
        await activate(t, 'license-detail-retry', keyboard: true);
        await settleRead(t);
        expect(find.text('BODY Heading'), findsOneWidget);
        expect(entry.reads, 2);
        expect(collects, 1);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('$suite closing pending registry retires late result', (
      t,
    ) async {
      final gate = Completer<void>();
      final entry = Entry(['Late'], 'LATE');
      LicenseRegistry.addLicense(() async* {
        await gate.future;
        yield entry;
      });
      await mount(t, suite);
      await activate(t, 'open', keyboard: true);
      await visibleFrames(t);
      await activate(t, 'license-back', keyboard: true);
      await visibleFrames(t);
      expect(find.byType(ThirdPartyLicenseBrowser), findsNothing);
      gate.complete();
      await settleRead(t);
      expect(entry.reads, 0);
      expect(find.textContaining('LATE'), findsNothing);
      await remove(t);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      '$suite active pointer row retains feedback and keyboard content lands instantly',
      (t) async {
        LicenseRegistry.addLicense(() async* {
          yield Entry(['App'], 'BODY');
        });
        await mount(t, suite);
        await activate(t, 'open');
        await settleRead(t);
        await activate(t, 'license-package-App');
        await t.pump();
        expect(t.hasRunningAnimations, isTrue);
        await settleRead(t);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await visibleFrames(t);
        await activate(t, 'license-package-App', keyboard: true);
        await settleRead(t);
        expectInstantDetails(t);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );
  }
}
