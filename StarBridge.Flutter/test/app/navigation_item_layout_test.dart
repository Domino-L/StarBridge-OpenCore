import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

void main() {
  for (final selected in [false, true]) {
    testWidgets(
      'collapsed icon stays centered with changing unread count selected=$selected',
      (tester) async {
        final count = ValueNotifier(0);
        addTearDown(count.dispose);
        var clicks = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              const Locale('en'),
            ),
            locale: const Locale('en'),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 56,
                  child: ShellNavigationItem(
                    descriptor: FeatureDescriptor(
                      id: 'room',
                      route: '/room',
                      labelKey: 'navigation.rooms',
                      descriptionKey: 'navigation.rooms',
                      icon: StarBridgeIconSemantic.room,
                      navigationRegion: NavigationRegion.primary,
                      order: 0,
                      buildDestination: (_) => const SizedBox(),
                      attentionCount: count,
                    ),
                    mode: ShellLayoutMode.iconOnly,
                    selected: selected,
                    onPressed: () => clicks++,
                    onKeyboardPressed: () {},
                    onPrevious: () {},
                    onNext: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final center = tester.getCenter(find.byType(ShellNavigationItem));
        for (final unread in [0, 1, 99, 100, 0]) {
          count.value = unread;
          await tester.pump();
          final icon = tester.getRect(find.byType(StarBridgeIcon));
          expect(icon.center.dx, closeTo(center.dx, .01));
          expect(icon.center.dy, closeTo(center.dy, .01));
          if (unread > 0) {
            final badge = tester.getRect(find.byType(AttentionCount));
            expect(badge.center.dx, greaterThan(icon.center.dx));
            expect(badge.center.dy, lessThan(icon.center.dy));
            expect(
              badge.right,
              lessThanOrEqualTo(
                tester.getRect(find.byType(ShellNavigationItem)).right,
              ),
            );
          }
        }
        await tester.tap(find.byType(StarBridgeIcon));
        expect(clicks, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
