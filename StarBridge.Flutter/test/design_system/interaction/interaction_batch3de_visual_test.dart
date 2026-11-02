import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3de_flows_test.dart' show MotionStore, frames;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<List<int>?> capture(WidgetTester t, GlobalKey key, String? name) =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      try {
        if (name != null) {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
          final file = File('build/reviews/interaction-batch3de/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png);
        }
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List()
            .toList();
      } finally {
        image.dispose();
      }
    });

void main() {
  setUpAll(loadFonts);
  final geometry = <String, List<Rect>>{};
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$suite light=$light scale=$scale card geometry and pointer cancellation',
          (t) async {
            size(t, const Size(1400, 1800));
            final owner = InMemoryAppPreferences();
            final frame = GlobalKey();
            final prefix =
                '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
            try {
              Widget page({bool reduce = false}) => scopedApp(
                MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(
                    key: frame,
                    child: GeneralSettingsPage(preferences: owner),
                  ),
                ),
                suite,
                light: light,
                reduce: reduce,
              );
              await t.pumpWidget(page());
              await t.pumpAndSettle();
              final ids = [
                'general-language-control-zh-CN',
                'general-language-control-en-US',
                'general-appearance-dark',
                'general-appearance-light',
              ];
              final absoluteRects = [
                for (final id in ids) t.getRect(find.byKey(Key(id))),
              ];
              // The fixture centers the whole scroll view. Existing suite-specific
              // controls below this slice can change its total height; verify card
              // dimensions and mutual spacing, not the parent's global offset.
              final rects = [
                for (final rect in absoluteRects)
                  rect.shift(-absoluteRects.first.topLeft),
              ];
              final geometryKey = '$light-$scale';
              if (suite == InteractionSuite.standard) {
                geometry[geometryKey] = rects;
              } else {
                expect(
                  rects,
                  geometry[geometryKey],
                  reason: 'feedback must not reshape approved card layout',
                );
              }
              final before = await capture(t, frame, '$prefix-rest');
              final target = find.byKey(const Key('general-appearance-light'));
              final gesture = await t.startGesture(t.getCenter(target));
              await t.pump(const Duration(milliseconds: 120));
              await t.pump(const Duration(milliseconds: 80));
              expect(await capture(t, frame, '$prefix-pressed'), isNot(before));
              await gesture.cancel();
              await t.pumpAndSettle();
              expect(
                owner.projection.value.effective.appearanceMode,
                AppearanceMode.dark,
              );
              await capture(t, frame, '$prefix-cancelled');
              await t.pumpWidget(page(reduce: true));
              await t.pumpAndSettle();
              final reduced = await capture(t, frame, '$prefix-reduce');
              await t.pump(const Duration(milliseconds: 250));
              expect(await capture(t, frame, null), reduced);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              owner.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '$suite actual delayed initial read retains visible label and follows live reduced motion',
      (t) async {
        size(t, const Size(1400, 1100));
        final owner = AppPreferencesModule();
        final store = MotionStore()..delayedRead = true;
        final read = owner.attachStore(store);
        final frame = GlobalKey();
        try {
          Widget page(bool reduce) => scopedApp(
            RepaintBoundary(
              key: frame,
              child: GeneralSettingsPage(preferences: owner),
            ),
            suite,
            reduce: reduce,
          );
          await t.pumpWidget(page(false));
          await frames(t);
          expect(find.text('正在读取当前设备设置…'), findsOneWidget);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          expect(
            t.widget<Text>(find.text('正在读取当前设备设置…')).textAlign,
            TextAlign.center,
          );
          expect(
            t.getSize(find.byType(SuiteProgressBar)).width,
            greaterThan(100),
          );
          final initial = await capture(t, frame, '${suite.name}-initial-read');
          await t.pump(const Duration(milliseconds: 160));
          expect(
            await capture(t, frame, '${suite.name}-initial-moving'),
            isNot(initial),
          );
          await t.pumpWidget(page(true));
          await frames(t);
          expect(find.text('正在读取当前设备设置…'), findsOneWidget);
          expect(find.byType(SuiteProgressBar), findsNothing);
          expect(store.reads, hasLength(1));
          store.reads.single.complete(store.result());
          await read;
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('general-settings-loading')),
            findsNothing,
          );
          await t.pumpWidget(page(false));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('general-appearance-light')));
          await frames(t);
          expect(
            t.getSize(find.byType(SuiteProgressBar)).width,
            greaterThan(100),
          );
          final saving = await capture(t, frame, '${suite.name}-saving');
          await t.pump(const Duration(milliseconds: 160));
          expect(
            await capture(t, frame, '${suite.name}-saving-moving'),
            isNot(saving),
          );
          store.accept();
          await t.pumpAndSettle();
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
  }
}
