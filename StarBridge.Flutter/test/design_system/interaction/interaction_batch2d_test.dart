import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app, pixels;
import 'interaction_batch1_test.dart' show clientTheme;
import 'interaction_batch2c_test.dart' show DelayedStore;

const switchKey = Key('toggle');
const switchLabel = 'Launch at startup';

Widget control({required bool value, ValueChanged<bool>? onChanged}) =>
    StarBridgeSwitch(
      controlKey: switchKey,
      label: switchLabel,
      value: value,
      onChanged: onChanged,
    );

void main() {
  for (final suite in InteractionSuite.values) {
    for (final direction in TextDirection.values) {
      testWidgets('$suite full-size target and 200 percent text $direction', (
        tester,
      ) async {
        var calls = 0;
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            app(
              Directionality(
                textDirection: direction,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: control(value: false, onChanged: (_) => calls++),
                ),
              ),
              suite: suite,
            ),
          );
          await tester.pumpAndSettle();
          final node = tester.getSemantics(find.bySemanticsLabel(switchLabel));
          expect(node.rect.width, greaterThanOrEqualTo(48));
          expect(node.rect.height, greaterThanOrEqualTo(48));
          final rect = tester.getRect(find.byType(StarBridgeSwitch));
          await tester.tapAt(rect.topLeft + const Offset(5, 24));
          await tester.pumpAndSettle();
          expect(calls, 1);
          expect(tester.takeException(), isNull);
        } finally {
          handle.dispose();
        }
      });
    }

    testWidgets(
      '$suite keyboard interrupts pointer effects without owner response',
      (tester) async {
        var value = false, accept = true;
        var calls = 0;
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, update) => control(
                value: value,
                onChanged: (next) {
                  calls++;
                  if (accept) update(() => value = next);
                },
              ),
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(switchKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        accept = false;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();
        expect(calls, 2);
        expect(value, isTrue);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$suite every rapid pointer change has visual feedback', (
      tester,
    ) async {
      var value = false;
      final calls = <bool>[];
      final liveKey = GlobalKey(), staticKey = GlobalKey();
      late StateSetter rebuild;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, update) {
              rebuild = update;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RepaintBoundary(
                    key: liveKey,
                    child: SizedBox(
                      width: 100,
                      height: 70,
                      child: Center(
                        child: control(
                          value: value,
                          onChanged: (next) {
                            calls.add(next);
                            rebuild(() => value = next);
                          },
                        ),
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    key: staticKey,
                    child: Theme(
                      data: clientTheme(suite, reduce: true),
                      child: SizedBox(
                        width: 100,
                        height: 70,
                        child: Center(
                          child: StarBridgeSwitch(
                            value: value,
                            label: 'Static',
                            onChanged: (_) {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          suite: suite,
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(switchKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        expect(calls.length, i + 1);
        expect(
          await pixels(tester, liveKey),
          isNot(await pixels(tester, staticKey)),
        );
        await tester.pump(const Duration(milliseconds: 110));
      }
      expect(calls, [true, false, true, false, true]);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });

    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      testWidgets('$suite $key is immediate and retains keyboard focus', (
        tester,
      ) async {
        var value = false;
        var calls = 0;
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            app(
              StatefulBuilder(
                builder: (context, update) => control(
                  value: value,
                  onChanged: (next) {
                    calls++;
                    update(() => value = next);
                  },
                ),
              ),
              suite: suite,
            ),
          );
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(key);
          await tester.pump();
          await tester.pump();
          expect(calls, 1);
          final data = tester
              .getSemantics(find.bySemanticsLabel(switchLabel))
              .getSemanticsData();
          expect(data.flagsCollection.isToggled, Tristate.isTrue);
          expect(data.flagsCollection.isFocused, Tristate.isTrue);
          expect(tester.binding.hasScheduledFrame, isFalse);
          await tester.sendKeyEvent(key);
          await tester.pump();
          await tester.pump();
          expect(calls, 2);
          expect(value, isFalse);
        } finally {
          handle.dispose();
        }
      });
    }

    testWidgets('$suite reader has one toggle and immediate activation', (
      tester,
    ) async {
      var value = false;
      var calls = 0;
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, update) => control(
                value: value,
                onChanged: (next) {
                  calls++;
                  update(() => value = next);
                },
              ),
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        final target = find.bySemanticsLabel(switchLabel);
        expect(target, findsOneWidget);
        final node = tester.getSemantics(target);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump();
        expect(calls, 1);
        expect(value, isTrue);
        expect(tester.binding.hasScheduledFrame, isFalse);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('$suite disabled rejects pointer keyboard and reader input', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(app(control(value: true), suite: suite));
        await tester.pumpAndSettle();
        final node = tester.getSemantics(find.bySemanticsLabel(switchLabel));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        expect(
          node.getSemanticsData().flagsCollection.isEnabled,
          Tristate.isFalse,
        );
        await tester.tap(find.byKey(switchKey), warnIfMissed: false);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          tester.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(switchLabel))
              .getSemanticsData()
              .flagsCollection
              .isFocused,
          isNot(Tristate.isTrue),
        );
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('$suite without owner update does not invent a value', (
      tester,
    ) async {
      final calls = <bool>[];
      await tester.pumpWidget(
        app(control(value: false, onChanged: calls.add), suite: suite),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(switchKey));
      await tester.pumpAndSettle();
      expect(calls, [true]);
      expect(
        tester.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
        isFalse,
      );
    });

    testWidgets(
      '$suite live reduce stops entrance and further changes remain static',
      (tester) async {
        var value = false, reduce = false;
        var calls = 0;
        late StateSetter rebuild;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, update) {
              rebuild = update;
              return app(
                control(
                  value: value,
                  onChanged: (next) {
                    calls++;
                    rebuild(() => value = next);
                  },
                ),
                suite: suite,
                reduce: reduce,
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(switchKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        rebuild(() => reduce = true);
        await tester.pump();
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.byKey(switchKey));
          await tester.pump();
          await tester.pump();
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
        expect(calls, 6);
        expect(value, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    for (final succeeds in [true, false]) {
      testWidgets(
        '$suite real startup owner waits and rolls back success=$succeeds',
        (tester) async {
          final preferences = AppPreferencesModule(
            systemLocales: const [Locale('en')],
          );
          addTearDown(preferences.dispose);
          final store = DelayedStore();
          await preferences.attachStore(store);
          await tester.pumpWidget(
            app(GeneralSettingsPage(preferences: preferences), suite: suite),
          );
          await tester.pumpAndSettle();
          final target = find.byKey(const Key('general-launch-at-startup'));
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pump();
          expect(store.writes, 1);
          expect(store.revision, 4);
          expect(
            preferences.projection.value.operation,
            AppPreferencesOperation.saving,
          );
          expect(
            preferences
                .projection
                .value
                .effective
                .applicationBehavior
                .launchAtStartup,
            isFalse,
          );
          expect(
            preferences
                .projection
                .value
                .confirmed!
                .applicationBehavior
                .launchAtStartup,
            isTrue,
          );
          final adapter = find.byWidgetPredicate(
            (w) =>
                w is StarBridgeSwitch &&
                w.controlKey == const Key('general-launch-at-startup'),
          );
          expect(tester.widget<StarBridgeSwitch>(adapter).onChanged, isNull);
          expect(store.patch!.applicationBehavior!.startupChoiceMade, isTrue);
          expect(store.patch!.applicationBehavior!.startMinimized, isFalse);
          await tester.tap(target, warnIfMissed: false);
          await tester.pump();
          expect(store.writes, 1);
          if (succeeds) {
            store.pending.complete(
              AppPreferencesReadResult(
                values: store.values.apply(store.patch!),
                revision: 5,
                source: AppPreferencesSource.stored,
              ),
            );
          } else {
            store.pending.completeError(
              const AppPreferencesStoreException(
                AppPreferencesFailure.saveFailed,
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(
            preferences
                .projection
                .value
                .effective
                .applicationBehavior
                .launchAtStartup,
            !succeeds,
          );
          expect(tester.widget<StarBridgeSwitch>(adapter).onChanged, isNotNull);
          expect(store.writes, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
