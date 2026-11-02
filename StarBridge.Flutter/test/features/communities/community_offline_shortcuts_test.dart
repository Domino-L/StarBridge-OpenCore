import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_shortcuts.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_offline_directory_test.dart' show offlineLogo;
import 'community_image_test_support.dart' show settleCommunityImages;
import 'community_shortcuts_test.dart' show QueuedPort;

final class CachedShortcutsPort extends QueuedPort {
  String? failure;
  bool empty = false;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    if (failure != null) throw CommunityFailure(failure!);
    return CommunityDirectory(
      view,
      query,
      empty
          ? const []
          : const [
              CommunityCard(
                targetRef: '',
                organizationRef: 'cached:fixture',
                name: 'Retained Organization',
                displayOnly: true,
                logo: offlineLogo,
              ),
            ],
      cachedAtUtc: DateTime.utc(2026, 10, 14, 12),
      cacheComplete: false,
      displayVersion: 'a' * 32,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  for (final locale in AppStrings.supportedLocales) {
    for (final iconOnly in [false, true]) {
      testWidgets(
        'cached organizations are passive, bounded and labelled in $locale iconOnly=$iconOnly',
        (tester) async {
          final port = CachedShortcutsPort();
          final model = CommunitiesModule(port);
          var navigations = 0;
          await tester.pumpWidget(
            _app(
              locale,
              model,
              iconOnly: iconOnly,
              activate: () async {
                navigations++;
                return true;
              },
            ),
          );
          await settleCommunityImages(tester);
          final strings = AppStrings.resolve(locale);
          if (!iconOnly) {
            expect(
              find.text(strings.text('communities.cachedOrganizations')),
              findsOneWidget,
            );
            expect(
              find.textContaining(
                strings
                    .text('communities.shortcutsCachedPartial')
                    .split('{time}')
                    .first,
              ),
              findsOneWidget,
            );
          }
          final row = tester.widget<StarBridgeActionRow>(
            find.byType(StarBridgeActionRow),
          );
          expect(row.onActivate, isNull);
          expect(find.byType(Image), findsOneWidget);
          await tester.tapAt(tester.getCenter(find.byType(StarBridgeActionRow)));
          await tester.pump();
          expect(navigations, 0);
          expect(port.writes, isEmpty);
          expect(model.selected, isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          model.dispose();
        },
      );
    }
    for (final missing in [false, true]) {
      testWidgets(
        'empty cached list and unavailable snapshot are distinct in $locale missing=$missing',
        (tester) async {
          final port = CachedShortcutsPort()..empty = true;
          if (missing) port.failure = 'offlineCacheUnavailable';
          final model = CommunitiesModule(port);
          await tester.pumpWidget(_app(locale, model));
          await tester.pumpAndSettle();
          final strings = AppStrings.resolve(locale);
          expect(
            find.text(
              strings.text(
                'communities.${missing ? 'shortcutsCacheUnavailable' : 'shortcutsCachedEmpty'}',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.text(strings.text('communities.shortcutsLoadFailed')),
            findsNothing,
          );
          expect(
            find.text(strings.text('communities.noJoinedShortcuts')),
            findsNothing,
          );
          await tester.pump(const Duration(seconds: 12));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          model.dispose();
        },
      );
    }
  }
}

Widget _app(
  Locale locale,
  CommunitiesModule model, {
  bool iconOnly = false,
  Future<bool> Function()? activate,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  home: Scaffold(
    body: SizedBox(
      width: iconOnly ? 56 : 260,
      child: CommunityShortcuts(
        module: model,
        iconOnly: iconOnly,
        selected: false,
        activate: activate ?? () async => true,
      ),
    ),
  ),
);
