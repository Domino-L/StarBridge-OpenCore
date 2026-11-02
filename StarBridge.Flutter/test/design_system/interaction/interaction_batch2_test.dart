import 'dart:async';
import 'dart:ui' show SemanticsAction, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/components/coming_soon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';
import 'package:starbridge_flutter/features/settings/client_license_dialog.dart';
import 'package:starbridge_flutter/features/settings/settings_capability_catalog.dart';
import 'package:starbridge_flutter/features/settings/settings_capability_overview.dart';
import 'package:starbridge_flutter/features/settings/settings_entry_dialog.dart';

import 'interaction_batch1_test.dart' show clientTheme;

Widget app(
  Widget child, {
  required InteractionSuite suite,
  bool reduce = false,
  bool light = false,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: clientTheme(suite, reduce: reduce, light: light),
  themeAnimationDuration: Duration.zero,
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(body: Center(child: child)),
);

final capability = SettingsCapabilityCatalog.planned.singleWhere(
  (entry) => entry.id == 'local-data-storage',
);

Widget entry({Map<String, SettingsEntryOpener> openers = const {}}) =>
    SettingsEntryOverrides(
      openers: openers,
      child: PlannedSettingsCapabilities(
        section: capability.section,
        capabilityIds: {capability.id},
      ),
    );

Future<void> pressKeyboardOpen(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

Future<List<int>> pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
        return bytes!.buffer.asUint8List().toList();
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite repeated row presses retain painted feedback', (
      tester,
    ) async {
      final repaint = GlobalKey();
      var calls = 0;
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: repaint,
            child: SizedBox(
              width: 240,
              child: StarBridgeActionRow(
                controlKey: const Key('row'),
                onActivate: (_, _) => calls++,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Active feedback'),
                ),
              ),
            ),
          ),
          suite: suite,
        ),
      );
      await tester.pumpAndSettle();
      final still = await pixels(tester, repaint);
      for (var i = 0; i < 5; i++) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('row'))),
        );
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          await pixels(tester, repaint),
          isNot(orderedEquals(still)),
          reason: 'Every active press must paint feedback, not just call the business callback.',
        );
        await gesture.up();
        expect(calls, i + 1);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$suite row pointer feedback never delays or drops commands', (
      tester,
    ) async {
      final sources = <InteractionSource>[];
      await tester.pumpWidget(
        app(
          StarBridgeActionRow(
            controlKey: const Key('row'),
            onActivate: (context, source) {
              expect(StarBridgeActivationOrigin.sourceOf(context), source);
              expect(InteractionScope.of(context).suite, suite);
              sources.add(source);
            },
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Row'),
            ),
          ),
          suite: suite,
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(const Key('row')));
        expect(sources.length, i + 1);
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(sources, everyElement(InteractionSource.pointer));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$suite row keyboard origin is synchronous through legacy context',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final sources = <InteractionSource>[];
        await tester.pumpWidget(
          app(
            StarBridgeActionRow(
              focusNode: focus,
              onActivate: (context, source) {
                sources.add(source);
                expect(
                  StarBridgeActivationOrigin.sourceOf(context),
                  InteractionSource.keyboard,
                );
              },
              child: const Text('Row'),
            ),
            suite: suite,
          ),
        );
        focus.requestFocus();
        await tester.pump();
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
        ]) {
          await tester.sendKeyEvent(key);
          expect(sources.last, InteractionSource.keyboard);
        }
        expect(sources.length, 2);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    for (final enabled in [true, false]) {
      testWidgets(
        '$suite row semantics preserve label and activation; enabled=$enabled',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            var calls = 0;
            await tester.pumpWidget(
              app(
                StarBridgeActionRow(
                  controlKey: const Key('row'),
                  onActivate: enabled
                      ? (context, source) {
                          expect(source, InteractionSource.keyboard);
                          expect(
                            StarBridgeActivationOrigin.sourceOf(context),
                            InteractionSource.keyboard,
                          );
                          calls++;
                        }
                      : null,
                  child: const Text('Readable row'),
                ),
                suite: suite,
              ),
            );
            await tester.pumpAndSettle();
            final node = tester.getSemantics(find.byKey(const Key('row')));
            final data = node.getSemanticsData();
            expect(data.label, contains('Readable row'));
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.hasAction(SemanticsAction.tap), enabled);
            if (enabled) {
              tester.binding.renderViews.single.owner!.semanticsOwner!
                  .performAction(node.id, SemanticsAction.tap);
              expect(calls, 1);
            } else {
              await tester.tap(
                find.byKey(const Key('row')),
                warnIfMissed: false,
              );
              expect(calls, 0);
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          } finally {
            handle.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite available entry retains its only opener and every command',
      (tester) async {
        final sources = <InteractionSource>[];
        await tester.pumpWidget(
          app(
            entry(
              openers: {
                capability.id: (context) async =>
                    sources.add(StarBridgeActivationOrigin.sourceOf(context)),
              },
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        final target = find.byKey(Key('settings-capability-${capability.id}'));
        for (var i = 0; i < 5; i++) {
          await tester.tap(target);
          expect(sources.length, i + 1);
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(sources.length, 6);
        expect(sources.last, InteractionSource.keyboard);
        expect(find.byType(SettingsCapabilityEntryDialog), findsNothing);
        expect(find.byType(ComingSoonBadge), findsNothing);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite unavailable entry remains informational with instant keyboard route',
      (tester) async {
        final links = InteractionScope.debugLiveLinks;
        await tester.pumpWidget(app(entry(), suite: suite));
        await tester.pumpAndSettle();
        await pressKeyboardOpen(tester);
        final dialog = find.byKey(Key('settings-entry-${capability.id}'));
        final route = ModalRoute.of(tester.element(dialog))!;
        expect(route, isA<StarBridgeDialogRoute<void>>());
        expect(route.animation!.value, 1);
        expect(find.byType(ComingSoonSection), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(Switch), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(dialog, findsNothing);
        expect(InteractionScope.debugLiveLinks, links);
        // Closing a route must restore the opener, not leave focus in the
        // removed modal. A second Enter opens the same entry immediately.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(dialog, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(dialog, findsNothing);
        expect(InteractionScope.debugLiveLinks, links);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite open entry follows live theme and reduced motion in two frames',
      (tester) async {
        final changes = ValueNotifier(false);
        addTearDown(changes.dispose);
        await tester.pumpWidget(
          ValueListenableBuilder<bool>(
            valueListenable: changes,
            builder: (_, updated, _) =>
                app(entry(), suite: suite, light: updated, reduce: updated),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key('settings-capability-${capability.id}')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        changes.value = true;
        await tester.pump();
        await tester.pump();
        final context = tester.element(
          find.byKey(Key('settings-entry-${capability.id}')),
        );
        final route = ModalRoute.of(context)! as StarBridgeDialogRoute<void>;
        expect(InteractionScope.of(context).reduceMotion, isTrue);
        expect(
          InteractionScope.of(context).palette.brightness,
          Brightness.light,
        );
        expect(route.animation!.status, AnimationStatus.completed);
        expect(
          tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last.color,
          route.barrierColor,
        );
        await tester.tap(find.byKey(const Key('settings-entry-close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite license stays pending; Esc discards no data and late read cannot reopen',
      (tester) async {
        final pending = Completer<ClientLicenseDocument>();
        var reads = 0;
        await tester.pumpWidget(
          app(
            ClientLicenseButton(
              open: (context) => showClientLicenseDialog(
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
        await pressKeyboardOpen(tester);
        final route = ModalRoute.of(
          tester.element(find.byKey(const Key('client-license-dialog'))),
        )!;
        expect(route.animation!.value, 1);
        expect(reads, 1);
        expect(find.byKey(const Key('client-license-body')), findsNothing);
        await tester.tap(
          find.byKey(const Key('client-license-retry')),
          warnIfMissed: false,
        );
        expect(reads, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('client-license-dialog')), findsNothing);
        pending.complete(
          const ClientLicenseDocument(
            ClientLicenseState.ready,
            'Exact unchanged body',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('client-license-body')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite license failure and retry preserve full document without consent action',
      (tester) async {
        var reads = 0;
        const text = 'Exact full body\r\n原文 preserved\r\nEnd';
        await tester.pumpWidget(
          app(
            ClientLicenseButton(
              open: (context) => showClientLicenseDialog(
                context,
                read: () async {
                  reads++;
                  if (reads == 1) throw StateError('private failure detail');
                  return const ClientLicenseDocument(
                    ClientLicenseState.ready,
                    text,
                  );
                },
              ),
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('client-license-open')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('client-license-error')), findsOneWidget);
        expect(find.textContaining('private'), findsNothing);
        await tester.tap(find.byKey(const Key('client-license-retry')));
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const Key('client-license-body')),
              )
              .data,
          text,
        );
        expect(find.byType(Checkbox), findsNothing);
        await tester.tap(find.byKey(const Key('client-license-close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
