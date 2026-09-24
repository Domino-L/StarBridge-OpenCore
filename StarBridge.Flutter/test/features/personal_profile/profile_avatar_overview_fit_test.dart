import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_avatar.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_hangar_overview.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

import '../communities/community_visitor_profile_test.dart' show VisitorPort;
import '../friends/social_layout_test.dart' show loadFonts, capture;
import 'profile_polish_regression_test.dart' show app, logo;

void main() {
  setUpAll(loadFonts);
  testWidgets('decoded roster avatar survives menu to visitor page', (
    tester,
  ) async {
    final port = VisitorPort();
    addTearDown(port.changes.close);
    final navigation = UserPageNavigation()
      ..open = (context, builder, _) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (c) => Scaffold(body: builder(c))),
        );
      };
    await tester.pumpWidget(
      UserInteractionScope(
        navigation: navigation,
        port: port,
        messagePage: null,
        child: app(
          UserAvatarMenu(
            name: 'Peer',
            target: UserTarget.community('a' * 32, 'b' * 32),
            avatarBytes: base64Decode(logo.split(',').last),
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(UserAvatarMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '查看资料'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PersonalProfileAvatar>(find.byType(PersonalProfileAvatar))
          .imageData,
      logo,
    );
    expect(
      find.descendant(
        of: find.byType(PersonalProfileAvatar),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final span in [1, 2]) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'overview span $span $locale $scale paints all text without ellipsis',
          (tester) async {
            final boundary = GlobalKey();
            await tester.pumpWidget(
              app(
                MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(
                    key: boundary,
                    child: SizedBox(
                      width: span == 1 ? 365 : 747,
                      height: 140,
                      child: PersonalProfileHangarOverview(
                        span: span,
                        summary: const PersonalProfileHangarSummary(
                          shipCount: 8,
                          manufacturerCount: 4,
                          primaryRoleKey: '',
                          estimatedValueLabel: '\$3,570 USD',
                          categories: [
                            PersonalProfileHangarCategorySlice(
                              labelKey: 'profile.local.category.combat',
                              count: 5,
                              category: PersonalProfileTagCategory.airCombat,
                            ),
                            PersonalProfileHangarCategorySlice(
                              labelKey: 'profile.local.category.industrial',
                              count: 3,
                              category: PersonalProfileTagCategory.industry,
                            ),
                          ],
                          recentlyAddedShip: null,
                          recentlyAddedShipImageAsset: '',
                          recentlyAddedAtLabel: '',
                          sourceLabelKey: '',
                          syncedAtLabel: '2026/9/21 12:00',
                        ),
                      ),
                    ),
                  ),
                ),
                locale: locale,
              ),
            );
            await tester.pumpAndSettle();
            for (final element in find.byType(RichText).evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: paragraph.text.toPlainText(),
              );
            }
            expect(tester.takeException(), isNull);
            if (locale == const Locale('zh', 'CN') && scale == 1) {
              await capture(tester, boundary, 'profile-overview-span-$span');
            }
            await tester.ensureVisible(
              find.byKey(const Key('profile-hangar-value-panel')),
            );
            await tester.pumpAndSettle();
            final valueRect = tester.getRect(find.text('\$3,570 USD'));
            final moduleRect = tester.getRect(
              find.byType(PersonalProfileHangarOverview),
            );
            expect(moduleRect.contains(valueRect.center), isTrue);
          },
        );
      }
    }
  }
}
