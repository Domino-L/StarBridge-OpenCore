import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_wallpaper_backdrop.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_wallpaper_catalog.dart';

void main() {
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
