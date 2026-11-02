import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/client_version_dialog.dart';

ThemeData clientTheme(
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) {
  final tokens = FutureRestraintStyle.resolve(
    light ? AppearanceMode.light : AppearanceMode.dark,
  ).withReducedMotion(reduce);
  final theme = buildStarBridgeTheme(tokens, const Locale('en'));
  return theme.copyWith(
    extensions: [
      ...theme.extensions.values,
      StarBridgeInteractionTheme(suite: suite),
    ],
  );
}

Widget harness(
  Widget child, {
  required InteractionSuite suite,
  bool reduce = false,
}) => MaterialApp(
  theme: clientTheme(suite, reduce: reduce),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite pointer burst invokes every callback immediately', (
      tester,
    ) async {
      final sources = <InteractionSource>[];
      await tester.pumpWidget(
        harness(
          StarBridgeActionButton(
            controlKey: const Key('action'),
            onActivate: sources.add,
            child: const Text('Action'),
          ),
          suite: suite,
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const Key('action')));
        expect(
          sources.length,
          i + 1,
          reason: 'No animation or burst may delay a command.',
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(sources, everyElement(InteractionSource.pointer));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$suite keyboard source stays static and immediate', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final sources = <InteractionSource>[];
      await tester.pumpWidget(
        harness(
          StarBridgeActionButton(
            controlKey: const Key('action'),
            focusNode: focus,
            onActivate: sources.add,
            child: const Text('Action'),
          ),
          suite: suite,
        ),
      );
      focus.requestFocus();
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.numpadEnter,
      ]) {
        await tester.sendKeyEvent(key);
        expect(sources.last, InteractionSource.keyboard);
      }
      expect(sources.length, 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$suite disabled control cannot activate via pointer or semantics',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          harness(
            const StarBridgeActionButton(
              controlKey: Key('action'),
              child: Text('Disabled'),
            ),
            suite: suite,
          ),
        );
        final node = tester.getSemantics(find.byKey(const Key('action')));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        await tester.tap(find.byKey(const Key('action')), warnIfMissed: false);
        await tester.pumpAndSettle();
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite keyboard opens real version route instantly and Esc closes',
      (tester) async {
        final links = InteractionScope.debugLiveLinks;
        await tester.pumpWidget(
          harness(
            ClientVersionButton(
              open: (context) => showClientVersionDialog(
                context,
                read: () async => 'verified.1',
              ),
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        final route = ModalRoute.of(
          tester.element(find.byKey(const Key('client-version-dialog'))),
        )!;
        expect(route, isA<StarBridgeDialogRoute<void>>());
        expect(route.animation!.value, 1);
        expect(route.animation!.status, AnimationStatus.completed);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('client-version-dialog')), findsNothing);
        expect(InteractionScope.debugLiveLinks, links);
        expect(tester.takeException(), isNull);
      },
    );

    for (final entering in [true, false]) {
      testWidgets(
        '$suite palette and reduced motion settle real scrim within two frames; entering=$entering',
        (tester) async {
          final settings = ValueNotifier((reduce: false, light: false));
          addTearDown(settings.dispose);
          await tester.pumpWidget(
            ValueListenableBuilder(
              valueListenable: settings,
              builder: (context, value, _) => MaterialApp(
                theme: clientTheme(
                  suite,
                  reduce: value.reduce,
                  light: value.light,
                ),
                themeAnimationDuration: Duration.zero,
                home: Scaffold(
                  body: Center(
                    child: ClientVersionButton(
                      open: (context) => showClientVersionDialog(
                        context,
                        read: () async => 'verified.2',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('client-version-open')));
          await tester.pump();
          if (entering) {
            await tester.pump(const Duration(milliseconds: 60));
          } else {
            await tester.pumpAndSettle();
          }
          settings.value = (reduce: true, light: true);
          await tester.pump();
          await tester.pump();
          final context = tester.element(
            find.byKey(const Key('client-version-dialog')),
          );
          final data = InteractionScope.of(context);
          final route = ModalRoute.of(context)!;
          expect(data.reduceMotion, isTrue);
          expect(data.palette.brightness, Brightness.light);
          final expectedScrim =
              (route as StarBridgeDialogRoute<void>).barrierColor;
          final actualScrim = tester
              .widgetList<ModalBarrier>(find.byType(ModalBarrier))
              .last
              .color;
          expect(
            actualScrim,
            expectedScrim,
            reason: 'Read actual painted barrier, not just route.barrierColor.',
          );
          expect(route.animation!.value, 1);
          expect(route.animation!.status, AnimationStatus.completed);
          await tester.tap(find.byKey(const Key('client-version-close')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite pending version read stays pending; no fabricated success',
      (tester) async {
        final pending = Completer<String?>();
        var reads = 0;
        await tester.pumpWidget(
          harness(
            ClientVersionButton(
              open: (context) => showClientVersionDialog(
                context,
                read: () {
                  reads++;
                  return pending.future;
                },
              ),
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('client-version-open')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump();
        expect(reads, 1);
        await tester.tap(
          find.byKey(const Key('client-version-retry')),
          warnIfMissed: false,
        );
        expect(reads, 1);
        expect(find.text('verified.3'), findsNothing);
        pending.complete('verified.3');
        await tester.pumpAndSettle();
        expect(find.text('verified.3'), findsOneWidget);
        await tester.tap(find.byKey(const Key('client-version-close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final light in [false, true]) {
    testWidgets('client tokens map without raw assets; light=$light', (
      tester,
    ) async {
      late InteractionData data;
      await tester.pumpWidget(
        MaterialApp(
          theme: clientTheme(InteractionSuite.scan, light: light),
          home: StarBridgeInteractionRegion(
            child: Builder(
              builder: (context) {
                data = InteractionScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final tokens = FutureRestraintStyle.resolve(
        light ? AppearanceMode.light : AppearanceMode.dark,
      );
      expect(data.palette.accent, tokens.colors.accent);
      expect(data.palette.surface, tokens.surfaces.panel.fill);
      expect(data.palette.focusRing, tokens.colors.focusRing);
      expect(data.suite, InteractionSuite.scan);
    });
  }

  testWidgets(
    'local system reduced-motion reaches scoped controls below navigator',
    (tester) async {
      late InteractionData data;
      await tester.pumpWidget(
        MaterialApp(
          theme: clientTheme(InteractionSuite.glow),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StarBridgeInteractionRegion(
              child: Builder(
                builder: (context) {
                  data = InteractionScope.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(data.reduceMotion, isTrue);
      expect(data.timed(data.motion.enter), Duration.zero);
    },
  );
}
