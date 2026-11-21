import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_modules.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';

import 'local_personal_profile_test.dart' show Harness, edit, shipA, shipB;

// 11-06: at most three favorite-ship modules. When full, the add menu no
// longer offers another one and says why in one plain line.
void main() {
  Future<List<PersonalProfileModuleLayoutItem>> pump(
    WidgetTester tester,
    Locale locale,
    int favorites,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final h = Harness();
    addTearDown(h.close);
    late PersonalProfileSnapshot snapshot;
    await tester.runAsync(() async {
      await h.port.save(edit(await h.port.read(), ids: [shipA, shipB]));
      snapshot = await h.port.read();
    });
    final projection = PersonalProfileProjection.fromSnapshot(snapshot);
    var layout = PersonalProfileLayout.normalize(projection.moduleLayout);
    for (var i = 0; i < 10; i++) {
      final hidden = layout.any(
        (e) => !e.isVisible && PersonalProfileModuleIds.isFavorite(e.moduleId),
      );
      if (!hidden && ProfileFavoriteModules.count(layout) >= favorites) break;
      layout = ProfileFavoriteModules.add(layout);
    }
    expect(ProfileFavoriteModules.count(layout), favorites);
    final changes = <List<PersonalProfileModuleLayoutItem>>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark)
              .withReducedMotion(true),
          locale,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PersonalProfileModuleGrid(
                projection: projection,
                visitorView: false,
                editing: true,
                layout: layout,
                onLayoutChanged: changes.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-layout-add-module')));
    await tester.pumpAndSettle();
    return changes.isEmpty ? layout : changes.last;
  }

  List<StarBridgeMenuEntry> entries(WidgetTester tester) => tester
      .widgetList<StarBridgeMenuAnchor>(find.byType(StarBridgeMenuAnchor))
      .expand((e) => e.entries)
      .toList();

  bool has(List<StarBridgeMenuEntry> list, String id) =>
      list.any((e) => e.id == ('profile-add-module', id));

  for (final locale in AppStrings.supportedLocales) {
    testWidgets('two favorite modules can still add a third $locale', (
      tester,
    ) async {
      await pump(tester, locale, 2);
      final list = entries(tester);
      expect(has(list, ProfileFavoriteModules.addAction), isTrue);
      expect(has(list, ProfileFavoriteModules.limitNotice), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('three favorite modules show the limit line instead $locale', (
      tester,
    ) async {
      await pump(tester, locale, 3);
      final list = entries(tester);
      expect(has(list, ProfileFavoriteModules.addAction), isFalse);
      final notice = list.singleWhere(
        (e) =>
            e.id == ('profile-add-module', ProfileFavoriteModules.limitNotice),
      );
      expect(notice.onActivate, isNull);
      final text = AppStrings.resolve(locale).text('profile.ships.moduleLimit');
      expect(text, contains('3'));
      expect(find.text(text), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
