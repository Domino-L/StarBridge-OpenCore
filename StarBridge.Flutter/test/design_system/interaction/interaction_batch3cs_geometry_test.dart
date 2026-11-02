import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/legal/cig_fankit_notice.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

// Original public native control is the geometry oracle, not a fixed golden.
Widget original(BuildContext context) {
  final tokens = context.tokens;
  return OutlinedButton.icon(
    key: const Key('geometry'),
    onPressed: () {},
    style: OutlinedButton.styleFrom(
      foregroundColor: tokens.colors.textPrimary,
      backgroundColor: tokens.surfaces.floating.fill,
      side: BorderSide(
        color: tokens.surfaces.floating.border,
        width: tokens.stroke.regular,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
    ),
    icon: StarBridgeIcon(
      StarBridgeIconSemantic.legalNotice,
      size: tokens.icons.small,
    ),
    label: Text(AppStrings.of(context).text('legal.fankit.inlineAction')),
  );
}

Future<void> checkGeometry(
  WidgetTester t,
  InteractionSuite suite, {
  Locale locale = const Locale('zh', 'CN'),
  double scale = 2,
  double width = 160,
  bool rtl = false,
  IconAlignment alignment = IconAlignment.start,
}) async {
  Future<(Size, Rect, Rect, double?)> sample(bool native) async {
    await t.pumpWidget(
      scopedApp(
        Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: locale,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    outlinedButtonTheme: OutlinedButtonThemeData(
                      style:
                          (OutlinedButtonTheme.of(context).style ??
                                  const ButtonStyle())
                              .copyWith(iconAlignment: alignment),
                    ),
                  ),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Center(
                      child: SizedBox(
                        width: width,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Builder(
                            builder: (context) => native
                                ? original(context)
                                : const CigFankitNoticeButton(
                                    key: Key('geometry'),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        suite,
      ),
    );
    await t.pumpAndSettle();
    final control = find.byKey(const Key('geometry'));
    final text = find.descendant(of: control, matching: find.byType(Text));
    expect(text, findsOneWidget);
    final icon = find.descendant(
      of: control,
      matching: find.byType(StarBridgeIcon),
    );
    final rect = t.getRect(control);
    final label = t.widget<Text>(text);
    final style = DefaultTextStyle.of(t.element(text)).style.merge(label.style);
    return (
      rect.size,
      t.getRect(text).shift(-rect.topLeft),
      t.getRect(icon).shift(-rect.topLeft),
      style.letterSpacing,
    );
  }

  final before = await sample(true);
  final actual = await sample(false);
  expect(actual, before);
  expect(t.takeException(), isNull);
  await t.pumpWidget(const SizedBox());
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en', 'US'),
    ]) {
      for (final scale in [1.0, 2.0]) {
        for (final width in [160.0, 360.0]) {
          testWidgets(
            'notice geometry $suite $locale text=$scale width=$width',
            (t) async {
              await checkGeometry(
                t,
                suite,
                locale: locale,
                scale: scale,
                width: width,
              );
            },
          );
        }
      }
    }
    for (final alignment in IconAlignment.values) {
      testWidgets('notice geometry $suite RTL end alignment=$alignment', (
        t,
      ) async {
        await checkGeometry(t, suite, rtl: true, alignment: alignment);
      });
    }
    testWidgets('notice $suite close retains original native hit geometry', (
      t,
    ) async {
      await t.pumpWidget(
        scopedApp(
          Center(
            child: IconButton(
              key: const Key('native-close'),
              onPressed: () {},
              icon: const StarBridgeIcon(StarBridgeIconSemantic.windowClose),
            ),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      final expected = t.getSize(find.byKey(const Key('native-close')));
      await t.pumpWidget(
        scopedApp(
          const Center(child: CigFankitNoticeButton(key: Key('open'))),
          suite,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('open')));
      await t.pumpAndSettle();
      expect(
        t.getSize(find.byKey(const Key('cig-fankit-notice-close'))),
        expected,
      );
      await t.pumpWidget(const SizedBox());
    });
  }
}
