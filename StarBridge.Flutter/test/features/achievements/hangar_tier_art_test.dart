import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/achievements/achievement_art.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievement_entry.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en'),
  ),
  home: Scaffold(body: child),
);

String _loaded(WidgetTester tester, Finder art) {
  final image = tester.widget<Image>(
    find.descendant(of: art, matching: find.byType(Image)),
  );
  return (image.image as AssetImage).assetName;
}

void main() {
  final hangar = achievementCatalog.where((d) => d.groupId == 'hangar');
  for (final d in hangar) {
    final prefix = d.id.replaceFirst('hangar-', '');
    test('${d.id}: all ranks and locked state select the right density', () {
      expect(d.earnedTierAssets, hasLength(5));
      expect(d.earnedTierDetailAssets, hasLength(5));
      for (final rank in [-8, 0, 1, 2, 3, 4, 5, 6, 99]) {
        for (final (size, dpr, resolution) in [
          (42.0, 1.0, 192),
          (64.0, 3.0, 192),
          (96.0, 3.0, 512),
          (240.0, 1.0, 512),
        ]) {
          for (final earned in [false, true]) {
            final tier = earned ? '${rank.clamp(1, 5)}' : 'locked';
            expect(
              d.artAsset(
                earned: earned,
                rank: rank,
                logicalSize: size,
                devicePixelRatio: dpr,
              ),
              'assets/achievements/$prefix-$tier-$resolution.webp',
            );
          }
        }
      }
      expect(
        d.artAsset(earned: true, logicalSize: 64, devicePixelRatio: 1),
        d.earnedTierAssets.first,
      );
    });
  }

  test('unranked artwork retains earned, locked and detail fallbacks', () {
    for (final d in achievementCatalog.where(
      (d) => d.earnedTierAssets.isEmpty,
    )) {
      for (final rank in [null, -1, 1, 5, 9]) {
        for (final earned in [false, true]) {
          for (final size in [64.0, 240.0]) {
            final list = earned ? d.earnedAsset : d.lockedAsset;
            final detail = earned ? d.earnedDetailAsset : d.lockedDetailAsset;
            expect(
              d.artAsset(
                earned: earned,
                rank: rank,
                logicalSize: size,
                devicePixelRatio: 1,
              ),
              size <= 192 ? list : detail ?? list,
            );
          }
        }
      }
    }
  });

  test('tier-only lists fall back to their own rank at detail density', () {
    const d = AchievementDefinition(
      id: 'synthetic-series',
      nameKey: '',
      conditionKey: '',
      memoryKey: '',
      earnedAsset: 'legacy',
      lockedAsset: 'gray',
      thresholds: [1, 2, 3, 4, 5],
      earnedTierAssets: ['one', 'two', 'three', 'four', 'five'],
    );
    expect(
      d.artAsset(earned: true, rank: 4, logicalSize: 240, devicePixelRatio: 2),
      'four',
    );
    expect(
      d.artAsset(earned: false, rank: 4, logicalSize: 240, devicePixelRatio: 2),
      'gray',
    );
  });

  test(
    'all 54 local assets decode at their stated transparent square size',
    () async {
      for (final d in hangar) {
        final prefix = d.id.replaceFirst('hangar-', '');
        for (final tier in ['1', '2', '3', '4', '5', 'locked']) {
          for (final (suffix, size) in [
            ('-192.webp', 192),
            ('-512.webp', 512),
            ('.png', 192),
          ]) {
            final asset = 'assets/achievements/$prefix-$tier$suffix';
            expect(File(asset).existsSync(), isTrue, reason: asset);
            final bytes = await rootBundle.load(asset);
            final codec = await ui.instantiateImageCodec(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
            final frame = await codec.getNextFrame();
            expect(
              (frame.image.width, frame.image.height),
              (size, size),
              reason: asset,
            );
            final pixels = (await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            expect(pixels[3], 0, reason: '$asset transparent corner');
            expect([
              for (var i = 3; i < pixels.length; i += 4) pixels[i],
            ], contains(255));
            if (tier == 'locked') {
              var neutral = true;
              for (var i = 0; i < pixels.length; i += 4) {
                if (pixels[i] != pixels[i + 1] || pixels[i] != pixels[i + 2]) {
                  neutral = false;
                  break;
                }
              }
              expect(neutral, isTrue, reason: '$asset neutral gray');
            }
            frame.image.dispose();
            codec.dispose();
          }
        }
      }
    },
    skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'),
  );

  testWidgets('entries pass the confirmed rank in row and wall layouts', (
    tester,
  ) async {
    final d = hangar.first;
    final collection = AchievementCollection(
      generation: 1,
      status: AchievementCollectionStatus.ready,
      earnedAt: {'${d.id}-3': DateTime.utc(2026, 11, 8)},
    );
    final focus = FocusNode();
    addTearDown(focus.dispose);
    for (final wall in [false, true]) {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 240,
            child: AchievementEntry(
              definition: d,
              collection: collection,
              focusNode: focus,
              onPressed: () {},
              wall: wall,
            ),
          ),
        ),
      );
      await tester
          .pumpAndSettle(); // localization delegate loads asynchronously
      expect(
        tester.widget<AchievementArt>(find.byType(AchievementArt)).rank,
        3,
      );
      // The asset actually loaded, not just the widget argument.
      expect(
        _loaded(tester, find.byType(AchievementArt)),
        startsWith('assets/achievements/home-3-'),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'detail shows each earned tier and locked gray for unearned tiers',
    (tester) async {
      final d = hangar.first;
      await tester.pumpWidget(
        _app(
          AchievementDetail(
            definition: d,
            collection: AchievementCollection(
              generation: 1,
              status: AchievementCollectionStatus.ready,
              earnedAt: {
                for (var rank = 1; rank <= 3; rank++)
                  '${d.id}-$rank': DateTime.utc(2026, 11, 8),
              },
            ),
          ),
        ),
      );
      await tester
          .pumpAndSettle(); // localization delegate loads asynchronously
      for (var rank = 1; rank <= 5; rank++) {
        final row = find.byKey(Key('achievement-rank-${d.id}-$rank'));
        final art = tester.widget<AchievementArt>(
          find.descendant(of: row, matching: find.byType(AchievementArt)),
        );
        expect(art.rank, rank);
        expect(art.earned, rank <= 3);
        expect(
          _loaded(
            tester,
            find.descendant(of: row, matching: find.byType(AchievementArt)),
          ),
          rank <= 3
              ? 'assets/achievements/home-$rank-192.webp'
              : 'assets/achievements/home-locked-192.webp',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
