import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/legal/cig_fankit_notice.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cn_visual_test.dart' as render;

Widget scaledApp(
  InteractionSuite suite,
  double scale,
  bool reduce,
  bool light,
) {
  final base = scopedApp(
    const Center(child: CigFankitNoticeButton(key: Key('visual-open'))),
    suite,
    reduce: reduce,
    light: light,
  ) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: base.theme,
    themeAnimationDuration: Duration.zero,
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: base.builder!(context, child),
    ),
    home: base.home,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final configuration in [
      (900.0, 1.0, true),
      (392.0, 1.0, false),
      (344.0, 2.0, false),
    ]) {
      testWidgets(
        '$suite notice frames width=${configuration.$1} text=${configuration.$2}',
        (t) async {
          size(t, Size(configuration.$1, 760));
          var reduce = false;
          late StateSetter update;
          final frame = GlobalKey();
          Future<void> capture(String stage) async {
            expect(t.takeException(), isNull);
            final bytes = await render.pixels(t, find.byKey(frame));
            await t.runAsync(() async {
              final directory = Directory('build/reviews/interaction-batch3cs')
                ..createSync(recursive: true);
              await File(
                '${directory.path}/${suite.name}-${configuration.$1.toInt()}-${configuration.$2}-$stage.png',
              ).writeAsBytes(bytes);
            });
          }

          try {
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: StatefulBuilder(
                  builder: (_, state) {
                    update = state;
                    return scaledApp(
                      suite,
                      configuration.$2,
                      reduce,
                      configuration.$3,
                    );
                  },
                ),
              ),
            );
            await t.pumpAndSettle();
            await capture('idle');
            await t.tap(find.byKey(const Key('visual-open')));
            await t.pump();
            await t.pump(const Duration(milliseconds: 80));
            await capture('enter');
            await t.pumpAndSettle();
            await capture('settled');
            final text = find.byKey(const Key('cig-fankit-required-notice'));
            expect(
              MediaQuery.textScalerOf(t.element(text)).scale(14),
              14 * configuration.$2,
            );
            await t.ensureVisible(text);
            await t.pumpAndSettle();
            await t.longPressAt(t.getTopLeft(text) + const Offset(16, 12));
            await t.pumpAndSettle();
            final editable = find.descendant(
              of: text,
              matching: find.byType(EditableText),
            );
            expect(editable, findsOneWidget);
            final value = t.widget<EditableText>(editable).controller.value;
            expect(value.text, CigFankitLegalNotice.requiredEnglish);
            expect(value.selection.isValid, isTrue);
            expect(value.selection.isCollapsed, isFalse);
            await capture('selection');
            update(() => reduce = true);
            await t.pump();
            await t.pump();
            expect(
              InteractionScope.of(
                t.element(find.byKey(const Key('cig-fankit-notice-close'))),
              ).reduceMotion,
              isTrue,
            );
            expect(ModalRoute.of(t.element(text))!.animation!.value, 1);
            await capture('reduced');
            await t.tap(find.byKey(const Key('cig-fankit-notice-close')));
            await t.pumpAndSettle();
            expect(find.byType(CigFankitNoticeContent), findsNothing);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pump();
          }
        },
      );
    }
  }
}
