import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/communities/community_gameplay_tags.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_shortcut_summary.dart';
import 'package:starbridge_flutter/shared/ships/ship_classification_tag.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

final _directory = visualOutputDir(
  'interaction_motion_batch3fo_20261017',
  legacySubdirectory: 'review',
);
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];

Future<void> _frames(WidgetTester t, [int count = 16]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

Future<List<int>> _pixels(WidgetTester t, GlobalKey key, {String? png}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      if (png != null) {
        await Directory(_directory).create(recursive: true);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_directory/$png.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List()
          .toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in _suites) {
    for (final light in [false, true]) {
      for (final locale in const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
      ]) {
        testWidgets(
          '3fo hints layout and live reduce ${suite.name} $light $locale',
          (t) async {
            final width = locale.languageCode == 'en' ? 900.0 : 540.0;
            size(t, Size(width, 700));
            final frame = GlobalKey();
            late StateSetter update;
            var reduce = false;
            final text = locale.languageCode == 'en'
                ? 'Heavy ground combat vehicle'
                : locale.countryCode == 'TW'
                ? '重型地面戰鬥載具'
                : '重型地面战斗载具';
            final base = scopedApp(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 160,
                          child: ShipClassificationTag(
                            label: text,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 60),
                        const CommunityGameplayTags(
                          value: '探索 · 战斗 · 运输 · 自定义玩法',
                          maxVisible: 2,
                        ),
                        const SizedBox(height: 60),
                        const OverlayShortcutSummary(
                          binding: 'Alt+F10',
                          enabled: true,
                          state: 'conflict',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              suite,
              light: light,
            ) as MaterialApp;
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return MaterialApp(
                      debugShowCheckedModeBanner: false,
                      locale: locale,
                      supportedLocales: base.supportedLocales,
                      localizationsDelegates: base.localizationsDelegates,
                      theme: base.theme,
                      themeAnimationDuration: Duration.zero,
                      builder: (context, child) =>
                          StarBridgeInteractionConfiguration(
                            suite: suite,
                            reduceMotion: reduce,
                            child: child!,
                          ),
                      home: base.home,
                    );
                  },
                ),
              ),
            );
            await _frames(t);
            final target = find.byType(ShipClassificationTag);
            final rect = t.getRect(target);
            final idle = await _pixels(t, frame);
            final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: const Offset(2, 2));
            await mouse.moveTo(t.getCenter(target));
            await t.pump(const Duration(milliseconds: 500));
            await _frames(t, 2);
            expect(
              t
                  .state<SuiteTooltipState>(
                    find.descendant(
                      of: target,
                      matching: find.byType(SuiteTooltip),
                    ),
                  )
                  .isShowing,
              isTrue,
            );
            update(() => reduce = true);
            await t.pump();
            await t.pump();
            final first = await _pixels(
              t,
              frame,
              png: locale == const Locale('zh', 'CN')
                  ? '${suite.name}-${light ? 'light' : 'dark'}-hint'
                  : null,
            );
            expect(
              first,
              isNot(equals(idle)),
              reason: 'real pointer hint remains visible',
            );
            await _frames(t, 30);
            expect(
              await _pixels(t, frame),
              first,
              reason: 'live reduce stops entrance and remains static',
            );
            expect(t.getRect(target), rect);
            expect(find.text('+2'), findsOneWidget);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(
              t
                  .state<SuiteTooltipState>(
                    find.descendant(
                      of: target,
                      matching: find.byType(SuiteTooltip),
                    ),
                  )
                  .isShowing,
              isFalse,
            );
            await mouse.removePointer();
            await t.pumpWidget(const SizedBox.shrink());
            await t.pump();
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
}
