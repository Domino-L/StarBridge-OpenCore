import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_ships.dart';
import 'package:starbridge_flutter/shared/inline_image_cache.dart';
import 'package:starbridge_flutter/shared/time_zone_label.dart';
import 'package:starbridge_flutter/shared/ships/ship_category_colors.dart';

import 'profile_polish_regression_test.dart' show app, logo;
import 'local_personal_profile_test.dart' show Harness;

void main() {
  testWidgets('changing UI language relabels time zones without changing IDs', (
    tester,
  ) async {
    const zoneId = 'Central America Standard Time';
    for (final entry in const [
      (Locale('zh', 'CN'), '中美洲标准时间'),
      (Locale('zh', 'TW'), '中美洲標準時間'),
      (Locale('en', 'US'), 'Central America Standard Time'),
    ]) {
      await tester.pumpWidget(
        app(
          Builder(builder: (context) => Text(timeZoneLabel(context, zoneId))),
          locale: entry.$1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
    }
  });
  testWidgets(
    'position edit reuses the main form and never saves before the main save',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness();
      final module = createPersonalProfileModule(h.port);
      await module.initialize();
      await tester.pumpWidget(app(PersonalProfilePage(module: module)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-positions-edit')), findsNothing);
      await tester.tap(find.byKey(const Key('profile-edit')));
      await tester.pumpAndSettle();
      final shortcut = find.byKey(const Key('profile-positions-edit'));
      await tester.ensureVisible(shortcut);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final pilot = find.byKey(const Key('profile-roles-pilot'));
      await tester.ensureVisible(pilot);
      await tester.tap(pilot);
      await tester.pumpAndSettle();
      expect(h.connection.content, isNull);
      final save = find.byKey(const Key('profile-save'));
      h.connection.failSave = true;
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
      expect(tester.widget<FilterChip>(pilot).selected, isFalse);
      h.connection.failSave = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(h.connection.content, isNotNull);
      expect(find.byKey(const Key('profile-positions-edit')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
      await tester.runAsync(h.session.close);
    },
  );

  testWidgets('small favorite thumbnails request bounded decode dimensions', (
    tester,
  ) async {
    final snapshot = await InMemoryPersonalProfileAdapter.forReview(
      signedIn: true,
    ).read();
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 760,
          height: 140,
          child: PersonalProfileFavoriteShips(
            ships: snapshot.favoriteShips,
            span: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      expect(
        widget.image,
        isA<ResizeImage>(),
        reason: 'Small cards must not decode full-size ship artwork',
      );
      expect((widget.image as ResizeImage).width, 128);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'time zone names and ship accents use current presentation rules',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              expect(
                timeZoneLabel(context, 'Central America Standard Time'),
                '中美洲标准时间',
              );
              expect(
                timeZoneLabel(context, 'Custom/Unknown', fallback: 'Kept'),
                'Kept',
              );
              expect(
                shipCategoryColor(context, 'competition'),
                const Color(0xFFFB6A22),
              );
              expect(
                shipCategoryColor(context, 'industrial'),
                const Color(0xFFFFD240),
              );
              expect(
                shipCategoryColor(context, 'ground-competition'),
                const Color(0xFFFF9C42),
              );
              return const SizedBox();
            },
          ),
        ),
      );
    },
  );

  test('inline image cache is bounded and clears on owner changes', () {
    final cache = InlineImageCache();
    cache.clear();
    final original = cache.resolve(logo);
    expect(cache.resolve(logo), same(original));
    for (var i = 0; i < InlineImageCache.maxEntries; i++) {
      cache.resolve('data:image/png;base64,${base64Encode([i, 10, 20])}');
    }
    expect(cache.resolve(logo), isNot(same(original)));
    final renewed = cache.resolve(logo);
    cache.clear();
    expect(cache.resolve(logo), isNot(same(renewed)));
    expect(cache.resolve('data:image/png;base64,???'), isNull);
    expect(cache.resolve('https://example.invalid/image.png'), isNull);
    cache.clear();
  });
}
