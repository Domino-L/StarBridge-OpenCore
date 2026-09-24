import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/overlay_appearance_preview.dart';
import 'package:starbridge_flutter/design_system/styles/native_appearance_player.dart';

const _privateArtworkOnly = bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')
    ? 'Rendered appearance captures are not distributed with public source.'
    : false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native catalog contains released, content-free joined-module captures', () async {
    final root = Directory('assets/overlay-appearances');
    final manifest = jsonDecode(
      File('${root.path}/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['renderer'], 'OverlayCompositionHudWindow');
    expect(manifest['content'], 'none');
    expect(manifest['modules'], [
      'left-top:Squads',
      'left-bottom:Members',
      'top-center:Notice',
      'right:Events',
    ]);
    final assets = manifest['assets'] as List<dynamic>;
    expect(assets.map((dynamic asset) => asset['id']), [
      'Default',
      'NightShadow',
    ]);
    expect(
      root.listSync().whereType<File>().where(
        // Selector artwork is independently tested, not a native module capture.
        (file) =>
            file.path.endsWith('.png') &&
            !file.path.endsWith('approved-board.png'),
      ),
      hasLength(
        [
          for (final id in ['Default', 'NightShadow', 'Verdict'])
            if (File('${root.path}/$id.png').existsSync()) id,
        ].length,
      ),
    );
    for (final dynamic asset in assets) {
      if (asset['id'] == 'NightShadow' &&
          !File('${root.path}/${asset['file']}').existsSync()) {
        continue;
      }
      final codec = await ui.instantiateImageCodec(
        File('${root.path}/${asset['file']}').readAsBytesSync(),
      );
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 2000);
      expect(frame.image.height, 760);
      final bytes = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      // Neutral background is opaque; each of the four module
      // interiors contains rendered material rather than an empty placeholder.
      for (final point in const [
        Offset(100, 180),
        Offset(100, 300),
        Offset(500, 60),
        Offset(800, 220),
      ]) {
        final offset =
            ((point.dy.toInt() * 2) * 2000 + point.dx.toInt() * 2) * 4;
        expect(bytes.getUint8(offset + 3), 255);
        expect([
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        ], isNot([8, 15, 20]));
      }
      if (asset['id'] == 'NightShadow') {
        // The native announcement anchor rests 31 logical pixels from its left
        // edge, at its vertical center. It must survive the content-free pass.
        final anchorOffset = (124 * 2000 + 602) * 4;
        expect(bytes.getUint8(anchorOffset), greaterThan(180));
        expect(bytes.getUint8(anchorOffset + 1), greaterThan(80));
      }
      frame.image.dispose();
      codec.dispose();
    }
  }, skip: _privateArtworkOnly);

  testWidgets('missing optional static artwork keeps a neutral preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _MissingPreviewAssets(),
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: OverlayAppearancePreview(appearanceId: 'NightShadow'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('overlay-native-preview-NightShadow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-native-preview-Default')),
      findsNothing,
    );
  });

  testWidgets(
    'cards display native images and never substitute a different skin',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Column(
              children: [
                OverlayAppearancePreview(appearanceId: 'Default'),
                OverlayAppearancePreview(appearanceId: 'NightShadow'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.map((image) => (image.image as AssetImage).assetName), [
        'assets/overlay-appearances/Default.png',
        'assets/overlay-appearances/NightShadow.png',
      ]);
      expect(images.every((image) => image.fit == BoxFit.contain), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const MaterialApp(
          home: OverlayAppearancePreview(appearanceId: 'Verdict'),
        ),
      );
      expect(find.byType(Image), findsNothing);
    },
  );

  test(
    'native animation contains changing frames for both luminous regions',
    () async {
      final codec = await ui.instantiateImageCodec(
        File('assets/overlay-appearances/NightShadow-flow.webp')
            .readAsBytesSync(),
      );
      expect(codec.frameCount, 161);
      expect(codec.repetitionCount, 0);
      var duration = Duration.zero;
      final signatures = <String, Set<int>>{'anchor': {}, 'event': {}};
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        duration += frame.duration;
        expect(frame.image.width, 2000);
        expect(frame.image.height, 760);
        final bytes = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final entry in const {
          'anchor': Rect.fromLTRB(570, 94, 675, 156),
          'event': Rect.fromLTRB(1890, 390, 1920, 550),
        }.entries) {
          var hash = 0;
          for (var y = entry.value.top.toInt(); y < entry.value.bottom; y++) {
            for (var x = entry.value.left.toInt(); x < entry.value.right; x++) {
              hash =
                  (hash * 31 + bytes.getUint8((y * 2000 + x) * 4)) & 0x7fffffff;
            }
          }
          signatures[entry.key]!.add(hash);
        }
        frame.image.dispose();
      }
      expect(duration, const Duration(milliseconds: 7000));
      for (final region in signatures.values) {
        expect(region.length, greaterThan(3));
      }
      codec.dispose();
    },
    skip: !File('assets/overlay-appearances/NightShadow-flow.webp').existsSync()
        ? 'Optional Night Shadow native artwork is not included in source builds.'
        : false,
  );

  testWidgets('both released cards repeat their native event-cycle specimen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            OverlayAppearancePreview(appearanceId: 'Default'),
            OverlayAppearancePreview(appearanceId: 'NightShadow'),
          ],
        ),
      ),
    );
    final players = tester.widgetList<NativeAppearancePlayer>(
      find.byType(NativeAppearancePlayer),
    );
    expect(players.map((player) => player.asset), [
      'assets/overlay-appearances/Default-event-cycle.webp',
      'assets/overlay-appearances/NightShadow-event-cycle.webp',
    ]);
    expect(
      players.every((player) => player.repeat && !player.controls),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'event cycles retain one-two-one native geometry across repetitions',
    () async {
      for (final skin in [
        'Default',
        if (File('assets/overlay-appearances/NightShadow-event-cycle.webp')
            .existsSync())
          'NightShadow',
      ]) {
        final codec = await ui.instantiateImageCodec(
          File('assets/overlay-appearances/$skin-event-cycle.webp')
              .readAsBytesSync(),
        );
        expect(codec.repetitionCount, -1);
        var elapsed = 0;
        final states = <int, bool>{};
        final silhouettes = <int, String>{};
        for (var i = 0; i < codec.frameCount * 2; i++) {
          final frame = await codec.getNextFrame();
          // Sample settled states over two full repeats, not frame numbers:
          // lossless WebP may combine identical consecutive native frames.
          for (final time in [0, 1640, 3000, 4160, 5600, 9400, 12000]) {
            if (elapsed <= time &&
                time < elapsed + frame.duration.inMilliseconds) {
              final bytes = (await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final offset = (600 * frame.image.width + 1600) * 4;
              if (time != 1640 && time != 4160) {
                states[time] =
                    bytes.getUint8(offset) != 8 ||
                    bytes.getUint8(offset + 1) != 15 ||
                    bytes.getUint8(offset + 2) != 20;
              }
              if (skin == 'NightShadow') {
                silhouettes[time] = [
                  for (var y = 550; y < 650; y++)
                    bytes.getUint8((y * frame.image.width + 1600) * 4) != 8 ||
                            bytes.getUint8(
                                  (y * frame.image.width + 1600) * 4 + 1,
                                ) !=
                                15 ||
                            bytes.getUint8(
                                  (y * frame.image.width + 1600) * 4 + 2,
                                ) !=
                                20
                        ? '1'
                        : '0',
                ].join();
              }
            }
          }
          elapsed += frame.duration.inMilliseconds;
          frame.image.dispose();
        }
        expect(elapsed, 12800);
        expect(states, {
          0: false,
          3000: true,
          5600: false,
          9400: true,
          12000: false,
        }, reason: skin);
        if (skin == 'NightShadow') {
          expect(
            silhouettes[1640],
            isNot(silhouettes[3000]),
            reason: 'New event must not instantly expand the fused chrome',
          );
          expect(
            silhouettes[4160],
            isNot(silhouettes[3000]),
            reason: 'Old event exit must reflow before removal',
          );
          expect(
            silhouettes[4160],
            isNot(silhouettes[5600]),
            reason: 'Reflow must include intermediate geometry',
          );
        }
        codec.dispose();
      }
    },
    skip: _privateArtworkOnly,
  );

  testWidgets(
    'motion can be paused and is disabled offstage or in background',
    (tester) async {
      Future<void> show({bool ticker = true, bool reduced = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: TickerMode(
                enabled: ticker,
                child: const OverlayAppearancePreview(appearanceId: 'Default'),
              ),
            ),
          ),
        );
      }

      String asset() =>
          find.byType(NativeAppearancePlayer).evaluate().isNotEmpty
          ? tester
                .widget<NativeAppearancePlayer>(
                  find.byType(NativeAppearancePlayer),
                )
                .asset
          : (tester.widget<Image>(find.byType(Image)).image as AssetImage)
                .assetName;
      await show();
      expect(asset(), endsWith('.webp'));
      await tester.tap(find.byKey(const Key('overlay-preview-motion-toggle')));
      await tester.pump();
      expect(asset(), endsWith('.png'));
      await tester.tap(find.byKey(const Key('overlay-preview-motion-toggle')));
      await tester.pump();
      expect(asset(), endsWith('.webp'));
      await show(ticker: false);
      expect(asset(), endsWith('.png'));
      await show();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(asset(), endsWith('.png'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(asset(), endsWith('.webp'));
      await show(reduced: true);
      expect(asset(), endsWith('.png'));
      expect(
        find.byKey(const Key('overlay-preview-motion-toggle')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

final class _MissingPreviewAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(FlutterError('Optional artwork is absent in this fixture'));
}
