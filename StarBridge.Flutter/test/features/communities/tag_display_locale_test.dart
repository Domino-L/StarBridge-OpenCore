import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_gameplay_tags.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_selected_tags.dart';

// English mode scan (CX-34, 2026-10-22): room gameplay tags and organization
// tags showed Simplified Chinese in every language. Saved values stay the
// WPF catalog names; only the visible text follows the app language.

Future<void> _pump(WidgetTester tester, Locale locale) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark),
      locale,
    ),
    home: Scaffold(
      body: Column(
        children: [
          // Saved organization tags are the catalog's Chinese names.
          const CommunityGameplayTags(value: '战斗'),
          RoomSelectedTags(
            tags: const [
              RoomTag(id: 'industry_salvage', text: '打捞', isGameplay: true),
            ],
            onRemove: (_, _) {},
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('English shows English room and organization tags', (
    tester,
  ) async {
    await _pump(tester, const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Combat'), findsOneWidget);
    expect(find.textContaining('Salvage'), findsOneWidget);
    expect(find.text('战斗'), findsNothing);
    expect(find.textContaining('打捞'), findsNothing);
  });

  testWidgets('Simplified Chinese keeps the catalog text', (tester) async {
    await _pump(tester, const Locale('zh', 'CN'));
    await tester.pumpAndSettle();
    expect(find.text('战斗'), findsOneWidget);
    expect(find.textContaining('打捞'), findsOneWidget);
  });
}
