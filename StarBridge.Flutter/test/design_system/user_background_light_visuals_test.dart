import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/frame_governor.dart';
import 'package:starbridge_flutter/design_system/appearance/cached_user_background.dart';
import 'package:starbridge_flutter/design_system/appearance/user_background.dart';

import '../support/light_visuals_test_support.dart';

Future<ui.Image> _texture(WidgetTester tester, {ui.Image? previous}) async {
  ui.Image? image;
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    // Fake time moves too, so the resize rest timer can fire.
    await tester.pump(const Duration(milliseconds: 20));
    image = tester
        .widget<RawImage>(find.byKey(const Key('user-background-cached-blur')))
        .image;
    if (image != null && !identical(image, previous)) return image;
  }
  throw StateError('Background texture did not finish');
}

void main() {
  late ValueNotifier<bool> light;
  setUp(() {
    light = ValueNotifier(false);
    debugLightVisualsOverride = light;
  });
  tearDown(() {
    debugLightVisualsOverride = null;
    light.dispose();
  });

  testWidgets(
    'background bakes once, invalidates inputs and disposes replaced images',
    (tester) async {
      // Test-owned files stay inside this Flutter workspace, never user data.
      final dir = Directory('build/cx-light-background-test');
      final firstFile = File('${dir.path}/first.png');
      final secondFile = File('${dir.path}/second.png');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAYAAADwdn+XAAAAFklEQVR4nGP4z8DwHx8mAo4aMPQNAADNZv8BGUNAhgAAAABJRU5ErkJggg==',
      );
      await tester.runAsync(() async {
        await dir.create(recursive: true);
        await firstFile.writeAsBytes(png);
        await secondFile.writeAsBytes(png);
      });
      addTearDown(() async {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        if (await firstFile.exists()) await firstFile.delete();
        if (await secondFile.exists()) await secondFile.delete();
      });
      var model = UserBackgroundImage(path: firstFile.path, blurSigma: 8);
      var size = const Size(640, 320);
      Widget surface() => lightVisualsApp(
        Center(
          child: SizedBox.fromSize(
            size: size,
            child: UserBackgroundLayer(image: model, scrimColor: Colors.black),
          ),
        ),
      );
      await pumpLightVisuals(tester, surface());
      expect(tester.layers.whereType<ImageFilterLayer>(), hasLength(1));
      light.value = true;
      await tester.pump();
      var current = await _texture(tester);
      expect(current.width, CachedUserBackground.maxDimension);
      expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
      expect(fractionalOpacityLayers(tester), isEmpty);
      // Rebuilding, repeated paints and scrim changes reuse the exact texture.
      model = model.copyWith(darken: .65);
      await pumpLightVisuals(tester, surface());
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester
            .widget<RawImage>(
              find.byKey(const Key('user-background-cached-blur')),
            )
            .image,
        same(current),
      );
      Future<void> changed() async {
        final previous = current;
        await pumpLightVisuals(tester, surface());
        current = await _texture(tester, previous: previous);
        expect(identical(current, previous), isFalse);
        expect(previous.debugDisposed, isTrue);
        expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
      }

      model = model.copyWith(blurSigma: 12);
      await changed();
      // A drag: each new size keeps the current texture on screen, and only
      // the rested size is baked.
      final beforeDrag = current;
      for (final width in [600.0, 520.0, 410.0]) {
        size = Size(width, width / 2);
        await pumpLightVisuals(tester, surface());
        expect(
          tester
              .widget<RawImage>(
                find.byKey(const Key('user-background-cached-blur')),
              )
              .image,
          same(beforeDrag),
        );
      }
      size = const Size(320, 160);
      await changed();
      expect(current.width, 320);
      model = model.copyWith(alignment: Alignment.bottomRight);
      await changed();
      model = model.copyWith(path: secondFile.path);
      await changed();
      final last = current;
      light.value = false;
      await tester.pump();
      expect(last.debugDisposed, isTrue);
      expect(tester.layers.whereType<ImageFilterLayer>(), hasLength(1));
      await pumpLightVisuals(tester, const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid light background never falls back to live blur', (
    tester,
  ) async {
    light.value = true;
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        const UserBackgroundLayer(
          image: UserBackgroundImage(
            path: 'build/cx-missing-background.png',
            blurSigma: 8,
          ),
          scrimColor: Colors.black,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
    expect(tester.takeException(), isNull);
    await pumpLightVisuals(tester, const SizedBox());
  });

  testWidgets(
    'removing a pending light background safely ignores late completion',
    (tester) async {
      light.value = true;
      await pumpLightVisuals(
        tester,
        lightVisualsApp(
          const CachedUserBackground(
            provider: AssetImage('assets/brand/default_banner_dark.png'),
            logicalSize: Size(800, 400),
            sigma: 8,
            alignment: Alignment.center,
          ),
        ),
      );
      await pumpLightVisuals(tester, const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
