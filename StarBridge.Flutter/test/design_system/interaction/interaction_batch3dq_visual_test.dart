import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/settings/first_use_privacy_dialog.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;
import 'interaction_batch3dq_test.dart';

Future<List<int>> firstPixels(WidgetTester t) => t
    .runAsync(() async {
      final render = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('3dq-frame')),
      );
      final image = await render.toImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List()
            .toList();
      } finally {
        image.dispose();
      }
    })
    .then((bytes) => bytes!);
Future<void> firstFrame(WidgetTester t, String name) async {
  final bytes = await firstPixels(t);
  await t.runAsync(() async {
    final file = File('build/reviews/interaction-batch3dq/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  });
}

void visibleFirst(WidgetTester t, Finder target) {
  final r = t.getRect(target);
  expect(r.left, greaterThanOrEqualTo(0));
  expect(r.right, lessThanOrEqualTo(400));
  expect(r.top, greaterThanOrEqualTo(0));
  expect(r.bottom, lessThanOrEqualTo(520));
}

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final locale in [
          const Locale('zh', 'CN'),
          const Locale('zh', 'TW'),
          const Locale('en'),
        ]) {
          final config =
              '${suite.name}-${light ? 'light' : 'dark'}-$scale-$locale';
          testWidgets(
            '$config notice actions, pinned pending/failure and live reduce stay usable',
            (t) async {
              fixture.size(t, const Size(400, 520));
              final probe = FirstProbe(),
                  outcome = FirstOutcome(),
                  dialog = probe.dialog();
              Widget app({bool reduce = false}) => firstApp(
                dialog,
                suite,
                outcome,
                light: light,
                reduce: reduce,
                scale: scale,
                locale: locale,
              );
              await t.pumpWidget(app());
              await t.pumpAndSettle();
              await t.tap(find.text('Open first privacy'));
              await t.pumpAndSettle();
              for (final action in ['accept', 'decline']) {
                visibleFirst(t, find.byKey(Key('first-privacy-$action')));
              }
              await firstFrame(t, '$config-idle');
              final adjust = find.byKey(const Key('first-privacy-adjust'));
              await t.ensureVisible(adjust);
              await t.pumpAndSettle();
              visibleFirst(t, adjust);
              expect(adjust.hitTestable(), findsOneWidget);
              // Accept remains a bottom action; do not reposition scroll for it.
              await t.tap(find.byKey(const Key('first-privacy-accept')));
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              expect(probe.choices, hasLength(1));
              visibleFirst(t, find.byType(HelpSupportWaiting));
              await firstFrame(t, '$config-pending');
              await t.pumpWidget(app(reduce: true));
              await t.pump();
              await t.pump();
              expect(find.byType(SuiteProgressBar), findsNothing);
              final before = await firstPixels(t);
              await t.pump(const Duration(milliseconds: 300));
              expect(await firstPixels(t), before);
              probe.gate.complete(false);
              await t.pump();
              await t.pump();
              final s = AppStrings.of(
                t.element(find.byType(FirstUsePrivacyDialog)),
              );
              visibleFirst(t, find.text(s.text('privacy.first.failed')));
              for (final action in ['accept', 'decline']) {
                visibleFirst(t, find.byKey(Key('first-privacy-$action')));
              }
              await firstFrame(t, '$config-failed');
              expect(outcome.done, isFalse);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            },
            timeout: const Timeout(Duration(seconds: 45)),
            skip: !Platform.isWindows,
          );
        }
      }
    }
  }
}
