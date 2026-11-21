import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_image_cache.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_images.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_presentation.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_stage_fill.dart';

// A maximized stage: 2560 wide, about 1072 left for the picture.
const _stage = Size(2560, 1072);

void main() {
  group('stage picture layout', () {
    test('16:9 stays whole at full height, the sides left to the backdrop', () {
      final art = LocalHangarStageFill.layoutFor(16 / 9, _stage);
      expect(art.size.height, _stage.height);
      expect(art.size.width, closeTo(_stage.height * 16 / 9, .01));
      expect(art.size.width, lessThan(_stage.width));
      expect(art.fill, isFalse);
      expect(art.fadeAcross, isTrue);
    });

    test('a tall picture stays whole at full height', () {
      const aspect = 1920 / 1822;
      final art = LocalHangarStageFill.layoutFor(aspect, _stage);
      expect(art.size.height, _stage.height);
      expect(art.size.width, closeTo(_stage.height * aspect, .01));
      expect(art.fill, isFalse);
      expect(art.fadeAcross, isTrue);
    });

    test('21:9 fills the stage', () {
      final art = LocalHangarStageFill.layoutFor(1920 / 823, _stage);
      expect(art.size, _stage);
      expect(art.fill, isTrue);
    });

    test('a far wider picture stays whole with bands above and below', () {
      const aspect = 1920 / 498;
      final art = LocalHangarStageFill.layoutFor(aspect, _stage);
      expect(art.size.width, _stage.width);
      expect(art.size.height, closeTo(_stage.width / aspect, .01));
      expect(art.fill, isFalse);
      expect(art.fadeAcross, isFalse);
    });

    test('an unknown shape keeps the whole box', () {
      final art = LocalHangarStageFill.layoutFor(null, _stage);
      expect(art.size, _stage);
    });
  });

  for (final c in const [
    (name: '16:9', w: 160, h: 90, fill: false),
    (name: 'tall', w: 100, h: 95, fill: false),
    (name: '21:9', w: 210, h: 90, fill: true),
  ]) {
    testWidgets(
      '${c.name} picture: whole, own backdrop behind, edges fade, no transition',
      (tester) async {
        const box = Size(1200, 500);
        tester.view
          ..physicalSize = const Size(1400, 700)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = _ImagePort(await tester.runAsync(() => _png(c.w, c.h)));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              const Locale('en'),
            ),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: box,
                  child: LocalHangarStageFill(
                    item: LocalHangarPresentation.fromSaved(
                      const LocalHangarShip(id: 'own', title: 'Own'),
                    ),
                    width: box.width,
                    height: box.height,
                    placeholder: const SizedBox.shrink(),
                    imagePort: port,
                    cache: LocalHangarImageCache(),
                    cacheKey: 'owner:own:content-0',
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        final expected = LocalHangarStageFill.layoutFor(c.w / c.h, box);
        final fade = find.byKey(const ValueKey('hangar-stage-edge-fade'));
        expect(fade, findsOneWidget);
        // The fade belongs to the picture's own edges, not to the stage's.
        expect(tester.getSize(fade).width, closeTo(expected.size.width, .5));
        expect(tester.getSize(fade).height, closeTo(expected.size.height, .5));
        expect(expected.fill, c.fill);
        final picture = tester.widget<Image>(
          find.descendant(of: fade, matching: find.byType(Image)),
        );
        expect(picture.fit, c.fill ? BoxFit.cover : BoxFit.contain);
        expect(
          tester
              .widget<Opacity>(
                find.ancestor(of: fade, matching: find.byType(Opacity)).first,
              )
              .opacity,
          1,
        );
        // Whatever the picture leaves free shows its own colors.
        final backdrop = find.byKey(
          const ValueKey('hangar-stage-own-backdrop'),
        );
        expect(backdrop, findsOneWidget);
        expect(tester.getSize(backdrop), box);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );
  }
}

Future<String> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366AA),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return 'data:image/png;base64,${base64Encode(data!.buffer.asUint8List())}';
}

class _ImagePort implements LocalHangarImagePort {
  _ImagePort(this.uri);
  final String? uri;
  @override
  Future<String?> readImage() async => uri;
  @override
  bool get canPickLogo => false;
  @override
  Future<CommunityLogoSource?> pickLogo() async => null;
  @override
  Future<String> cropLogo(String sourceRef, double x, double y, double size) =>
      throw StateError('No crop in image fixture');
  @override
  Future<void> clearLogo() async {}
  @override
  Future<void> saveImage() async {}
  @override
  Future<void> restoreImage() async {}
}
