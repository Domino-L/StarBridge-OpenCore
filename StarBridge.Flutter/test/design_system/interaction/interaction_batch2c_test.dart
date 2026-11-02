import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_segmented_control.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/features/settings/general_settings_behavior.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app, pixels;
import 'interaction_batch1_test.dart' show clientTheme;

const groupKey = Key('segments');
const choices = [
  StarBridgeSegment(value: 0, label: 'First'),
  StarBridgeSegment(value: 1, label: 'Second'),
];

Widget control({int value = 0, ValueChanged<int>? onChanged}) =>
    StarBridgeSegmentedControl<int>(
      controlKey: groupKey,
      segments: choices,
      value: value,
      onChanged: onChanged,
    );

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite disabled startup keeps the saved destination', (
      tester,
    ) async {
      var calls = 0;
      final value = ApplicationBehaviorPreferences.defaults.copyWith(
        startMinimized: true,
      );
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: GeneralSettingsBehavior(
              value: value,
              enabled: true,
              onChanged: (_) async {
                calls++;
                return true;
              },
            ),
          ),
          suite: suite,
        ),
      );
      await tester.pumpAndSettle();
      final adapter = find.byWidgetPredicate(
        (w) =>
            w is StarBridgeSegmentedControl<bool> &&
            w.controlKey == const Key('general-startup-behavior'),
      );
      expect(
        tester.widget<StarBridgeSegmentedControl<bool>>(adapter).value,
        isTrue,
      );
      expect(
        tester.widget<StarBridgeSegmentedControl<bool>>(adapter).onChanged,
        isNull,
      );
      final label = tester
          .widget<StarBridgeSegmentedControl<bool>>(adapter)
          .segments
          .first
          .label;
      await tester.tap(
        find.descendant(of: adapter, matching: find.text(label)),
        warnIfMissed: false,
      );
      expect(calls, 0);
    });

    for (final direction in TextDirection.values) {
      testWidgets(
        '$suite semantic target bounds track native layout $direction',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              app(
                Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(2),
                    ),
                    child: control(onChanged: (_) {}),
                  ),
                ),
                suite: suite,
              ),
            );
            await tester.pumpAndSettle();
            for (final label in ['First', 'Second']) {
              final node = tester.getSemantics(find.bySemanticsLabel(label));
              expect(node.rect.width, greaterThan(0));
              expect(node.rect.height, greaterThan(0));
              expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
            }
            expect(tester.takeException(), isNull);
          } finally {
            handle.dispose();
          }
        },
      );
    }

    testWidgets('$suite keyboard focus is exposed to the reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(app(control(onChanged: (_) {}), suite: suite));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final first = tester
            .getSemantics(find.bySemanticsLabel('First'))
            .getSemanticsData();
        expect(first.flagsCollection.isFocused, Tristate.isTrue);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('$suite repeated segmented presses paint feedback', (
      tester,
    ) async {
      var value = 0;
      var calls = 0;
      final repaint = GlobalKey();
      final reference = GlobalKey();
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, update) => app(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: repaint,
                  child: Material(
                    child: control(
                      value: value,
                      onChanged: (next) {
                        calls++;
                        update(() => value = next);
                      },
                    ),
                  ),
                ),
                Theme(
                  data: clientTheme(suite, reduce: true),
                  child: RepaintBoundary(
                    key: reference,
                    child: Material(
                      child: control(value: value, onChanged: (_) {}),
                    ),
                  ),
                ),
              ],
            ),
            suite: suite,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        final next = value == 0 ? 1 : 0;
        await tester.tap(
          find.descendant(
            of: find.byKey(repaint),
            matching: find.text(choices[next].label),
          ),
        );
        expect(calls, i + 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          await pixels(tester, repaint),
          isNot(equals(await pixels(tester, reference))),
          reason: 'Each active retarget must differ from the same-value static projection.',
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$suite quick reverse selects latest without losing callbacks',
      (tester) async {
        var value = 0;
        final calls = <int>[];
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, update) => control(
                value: value,
                onChanged: (next) {
                  calls.add(next);
                  update(() => value = next);
                },
              ),
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 8; i++) {
          final next = value == 0 ? 1 : 0;
          await tester.tap(find.text(choices[next].label));
          expect(calls.length, i + 1);
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(calls, [1, 0, 1, 0, 1, 0, 1, 0]);
        expect(value, 0);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );

    testWidgets('$suite keyboard activation is immediate and single-dispatch', (
      tester,
    ) async {
      final calls = <int>[];
      await tester.pumpWidget(app(control(onChanged: calls.add), suite: suite));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.numpadEnter,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      expect(calls, [1, 1, 1]);
    });

    for (final enabled in [true, false]) {
      testWidgets('$suite semantics activate one option; enabled=$enabled', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        try {
          var value = 0;
          final calls = <int>[];
          final splash = CountingSplashFactory();
          await tester.pumpWidget(
            app(
              StatefulBuilder(
                builder: (context, update) => Theme(
                  data: Theme.of(context).copyWith(splashFactory: splash),
                  child: control(
                    value: value,
                    onChanged: enabled
                        ? (next) {
                            calls.add(next);
                            update(() => value = next);
                          }
                        : null,
                  ),
                ),
              ),
              suite: suite,
            ),
          );
          await tester.pumpAndSettle();
          final named = find.bySemanticsLabel('Second');
          expect(named, findsOneWidget);
          final node = tester.getSemantics(named);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            enabled,
          );
          if (enabled) {
            tester.binding.renderViews.single.owner!.semanticsOwner!
                .performAction(node.id, SemanticsAction.tap);
            await tester.pump();
            await tester.pump();
            expect(calls, [1]);
            expect(value, 1);
            expect(
              splash.calls,
              0,
              reason: 'Read-screen activation must bypass native ink.',
            );
            if (suite != InteractionSuite.standard) {
              expect(tester.binding.hasScheduledFrame, isFalse);
            }
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.tap(find.text('Second'), warnIfMissed: false);
            expect(calls, isEmpty);
          }
        } finally {
          handle.dispose();
        }
      });
    }

    testWidgets(
      '$suite reduced motion interrupts retarget and keeps latest value',
      (tester) async {
        var value = 0;
        var reduce = false;
        var calls = 0;
        late StateSetter update;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setter) {
              update = setter;
              return app(
                control(
                  value: value,
                  onChanged: (next) => update(() {
                    value = next;
                    calls++;
                  }),
                ),
                suite: suite,
                reduce: reduce,
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Second'));
        await tester.pump(const Duration(milliseconds: 60));
        update(() => reduce = true);
        await tester.pump();
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          await tester.tap(find.text(value == 0 ? 'Second' : 'First'));
          await tester.pump();
        }
        expect(calls, 7);
        await tester.pumpAndSettle();
        expect(value, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );

    testWidgets('$suite presentation never invents an accepted value', (
      tester,
    ) async {
      final calls = <int>[];
      await tester.pumpWidget(app(control(onChanged: calls.add), suite: suite));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(calls, [1]);
      if (suite == InteractionSuite.standard) {
        expect(
          tester.widget<SegmentedButton<int>>(find.byKey(groupKey)).selected,
          {0},
        );
      } else {
        expect(
          tester.widget<SuiteSelectionTrack>(find.byKey(groupKey)).selected,
          0,
        );
      }
    });

    for (final succeeds in [true, false]) {
      testWidgets(
        '$suite real preference owner keeps save semantics success=$succeeds',
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
          final adapter = find.byWidgetPredicate(
            (w) =>
                w is StarBridgeSegmentedControl<bool> &&
                w.controlKey == const Key('general-close-behavior'),
          );
          await tester.ensureVisible(adapter);
          await tester.pumpAndSettle();
          final label = tester
              .widget<StarBridgeSegmentedControl<bool>>(adapter)
              .segments
              .singleWhere((e) => !e.value)
              .label;
          await tester.tap(
            find.descendant(of: adapter, matching: find.text(label)),
          );
          await tester.pump();
          expect(store.writes, 1);
          expect(store.revision, 4);
          expect(
            preferences.projection.value.operation,
            AppPreferencesOperation.saving,
          );
          // Existing owner deliberately projects the requested value while busy.
          expect(
            preferences
                .projection
                .value
                .effective
                .applicationBehavior
                .keepRunningInBackground,
            isFalse,
          );
          expect(
            preferences
                .projection
                .value
                .confirmed!
                .applicationBehavior
                .keepRunningInBackground,
            isTrue,
          );
          expect(
            tester.widget<StarBridgeSegmentedControl<bool>>(adapter).onChanged,
            isNull,
          );
          expect(
            store.patch!.applicationBehavior!.closeBehaviorChoiceMade,
            isTrue,
          );
          expect(store.patch!.applicationBehavior!.launchAtStartup, isTrue);
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
                .keepRunningInBackground,
            !succeeds,
          );
          expect(
            tester.widget<StarBridgeSegmentedControl<bool>>(adapter).onChanged,
            isNotNull,
          );
          expect(store.writes, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class DelayedStore implements AppPreferencesStore {
  final values = StoredAppPreferences(
    localeOverride: const Locale('en'),
    appearanceMode: AppPreferences.defaults.appearanceMode,
    motionPreference: MotionPreference.followSystem,
    applicationBehavior: ApplicationBehaviorPreferences.defaults.copyWith(
      launchAtStartup: true,
    ),
  );
  final pending = Completer<AppPreferencesReadResult>();
  int writes = 0;
  int? revision;
  AppPreferencesPatch? patch;
  @override
  Future<AppPreferencesReadResult> read() async => AppPreferencesReadResult(
    values: values,
    revision: 4,
    source: AppPreferencesSource.stored,
  );
  @override
  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch next, {
    required int expectedRevision,
  }) {
    writes++;
    patch = next;
    revision = expectedRevision;
    return pending.future;
  }

  @override
  void dispose() {}
}

class CountingSplashFactory extends InteractiveInkFeatureFactory {
  int calls = 0;
  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    calls++;
    return NoSplash.splashFactory.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}
