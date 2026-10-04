import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_wallpaper_backdrop.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_wallpaper_catalog.dart';

void main() {
  testWidgets(
    'transient image failure recovers without refreshing the profile',
    (tester) async {
      final bundle = _FailOnceBundle();
      final tokens = StyleRegistry()
          .resolve(FutureRestraintStyle.id, AppearanceMode.dark)
          .tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
          home: DefaultAssetBundle(
            bundle: bundle,
            child: const PersonalProfileWallpaperBackdrop(
              wallpaperId: 'formation-flight',
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(bundle.imageReads, 1);
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 40; i++) {
        if (find.byType(RawImage).evaluate().isNotEmpty &&
            tester.widget<RawImage>(find.byType(RawImage)).image != null) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(bundle.imageReads, 2);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'persistent image failure has bounded retries and is not silent',
    (tester) async {
      final bundle = _FailOnceBundle(alwaysFail: true);
      final tokens = StyleRegistry()
          .resolve(FutureRestraintStyle.id, AppearanceMode.dark)
          .tokens;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
          home: DefaultAssetBundle(
            bundle: bundle,
            child: const PersonalProfileWallpaperBackdrop(
              wallpaperId: 'formation-flight',
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(bundle.imageReads, 3);
      expect(find.text('背景未加载，可刷新页面重试'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(bundle.imageReads, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final mode in AppearanceMode.values) {
    testWidgets('image keeps a faint scrim in ${mode.name} mode', (
      tester,
    ) async {
      await _pumpBackdrop(tester, mode, 'formation-flight');

      final scrim = tester.widget<ColoredBox>(
        find.byKey(const Key('profile-wallpaper-scrim')),
      );
      expect(
        scrim.color,
        mode == AppearanceMode.dark
            ? Colors.black.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);

      final image = tester.widget<Image>(
        find.byKey(const Key('profile-wallpaper-image')),
      );
      expect(image.fit, BoxFit.cover);
      expect(
        image.alignment,
        PersonalProfileWallpaperCatalog.resolve('formation-flight')
            .focalAlignment,
      );
      for (final size in const [
        Size(1280, 720),
        Size(2560, 1080),
        Size(720, 1000),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const Key('profile-wallpaper-image'))),
          size,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('default background has no image scrim', (tester) async {
    await _pumpBackdrop(tester, AppearanceMode.dark, 'none');
    expect(find.byKey(const Key('profile-wallpaper-scrim')), findsNothing);
    expect(find.byKey(const Key('profile-wallpaper-image')), findsNothing);
    expect(find.byKey(const Key('profile-wallpaper-none')), findsOneWidget);
  });
}

class _FailOnceBundle extends CachingAssetBundle {
  _FailOnceBundle({this.alwaysFail = false});
  final bool alwaysFail;
  int imageReads = 0;
  @override
  Future<ByteData> load(String key) {
    if (key == 'assets/profile-wallpapers/formation-flight.jpg') {
      if (++imageReads == 1 || alwaysFail) {
        throw StateError('Synthetic transient asset read failure');
      }
      // Synthetic one-pixel PNG keeps retry coverage independent of artwork.
      return Future.value(
        ByteData.sublistView(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      );
    }
    return rootBundle.load(key);
  }
}

Future<void> _pumpBackdrop(
  WidgetTester tester,
  AppearanceMode mode,
  String wallpaperId,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final tokens = StyleRegistry().resolve(FutureRestraintStyle.id, mode).tokens;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
      home: PersonalProfileWallpaperBackdrop(wallpaperId: wallpaperId),
    ),
  );
  await tester.pumpAndSettle();
}
