import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/community_sharing_dialog.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dp_test.dart';

Future<void> loadVisualFonts() async {
  await fixture.loadFonts();
  if (!Platform.isWindows) return;
  // The product deliberately uses the Windows Traditional Chinese fallback.
  // flutter_tester disables system-font discovery; load installed files only
  // in this Windows review harness, never bundle or redistribute them.
  final loader = FontLoader('Microsoft JhengHei UI');
  for (final path in [
    'C:/Windows/Fonts/msjh.ttc',
    'C:/Windows/Fonts/msjhbd.ttc',
  ]) {
    final bytes = await File(path).readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<List<int>> pixels(WidgetTester t) => t
    .runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('3dp-frame')),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List()
          .toList();
      image.dispose();
      return bytes;
    })
    .then((value) => value!);
Future<void> saveFrame(WidgetTester t, String name) async {
  final bytes = await pixels(t);
  await t.runAsync(() async {
    final directory = Directory('build/reviews/interaction-batch3dp');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
  });
}

void visible(WidgetTester t, Finder f) {
  final rect = t.getRect(f);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(400));
  expect(rect.bottom, lessThanOrEqualTo(520));
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
          final name =
              '${suite.name}-${light ? 'light' : 'dark'}-$scale-$locale';
          testWidgets(
            '$name bounded consent / pinned pending and failure / live static reduce',
            (t) async {
              fixture.size(t, const Size(400, 520));
              final p = SharingProbe();
              final dialog = p.dialog();
              Widget app({bool reduce = false}) => sharingApp(
                dialog,
                suite,
                light: light,
                reduce: reduce,
                scale: scale,
                locale: locale,
              );
              await t.pumpWidget(app());
              await t.pumpAndSettle();
              await t.tap(find.text('Open'));
              await t.pumpAndSettle();
              for (final key in ['confirm', 'none']) {
                visible(t, find.byKey(Key('community-sharing-$key')));
              }
              await saveFrame(t, '$name-idle');
              // Tap the bottom action directly. Do not ensureVisible/re-align the
              // content beforehand; its own scroll can be anywhere.
              await t.drag(
                find.byType(SingleChildScrollView).last,
                const Offset(0, -2000),
              );
              await t.pumpAndSettle();
              await t.tap(find.byKey(const Key('community-sharing-confirm')));
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              visible(t, find.byType(HelpSupportWaiting));
              expect(p.calls, ['hangar']);
              await saveFrame(t, '$name-pending');
              await t.pumpWidget(app(reduce: true));
              await t.pump();
              await t.pump();
              expect(find.byType(SuiteProgressBar), findsNothing);
              final static = await pixels(t);
              await t.pump(const Duration(milliseconds: 300));
              expect(
                await pixels(t),
                static,
                reason: 'The real dialog and its backdrop must stop, not just the label.',
              );
              p.gates[0].complete(false);
              await t.pump();
              await t.pump();
              final failure = find.text(
                locale.languageCode == 'en'
                    ? 'Hangar settings could not be confirmed. Your choices are kept. Try again.'
                    : locale.countryCode == 'TW'
                    ? '機庫設定未能確認，選擇已保留。請重試。'
                    : '机库设置未能确认，选择已保留。请重试。',
              );
              visible(t, failure);
              for (final key in ['confirm', 'none']) {
                visible(t, find.byKey(Key('community-sharing-$key')));
              }
              await saveFrame(t, '$name-failed');
              expect(find.byType(CommunitySharingDialog), findsOneWidget);
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
