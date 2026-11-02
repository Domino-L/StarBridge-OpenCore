import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/overlay_appearance_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;
import 'overlay_appearance_configuration_test.dart' show fixture;

Map<String, Object?> headerFixture() {
  final bytes = Uint8List(45);
  bytes.setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
  bytes.setRange(12, 16, ascii.encode('IHDR'));
  final header = ByteData.sublistView(bytes);
  header.setUint32(8, 13);
  header.setUint32(16, 2);
  header.setUint32(20, 2);
  return {
    'format': 'png',
    'width': 2,
    'height': 2,
    'data': base64Encode(bytes),
  };
}

Future<Uint8List> tinyPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.red);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final installed =
      Platform.environment['STARBRIDGE_APPEARANCE_CONFIGURATION_FIXTURE'];
  final capture = Platform.environment['STARBRIDGE_APPEARANCE_POSTER_CAPTURE'];
  setUpAll(() async {
    if (capture != null) await loadFonts();
  });

  test('native poster is optional, bounded and detached from input/output', () {
    expect(OverlayAppearanceConfiguration.fromMap(fixture()).preview, isNull);
    expect(
      OverlayAppearanceConfiguration.fromMap(fixture()..['preview'] = null)
          .preview,
      isNull,
    );
    final source = headerFixture();
    final config = OverlayAppearanceConfiguration.fromMap(
      fixture()..['preview'] = source,
    );
    source['data'] = '';
    final first = config.preview!.bytes;
    first[0] = 0;
    expect(config.preview!.bytes[0], 137);
    expect(config.preview!.width, 2);
    expect(config.preview!.height, 2);
  });

  test(
    'poster rejects URLs, commands, mismatched headers and oversized data',
    () {
      for (final source in [
        headerFixture()..['format'] = 'jpeg',
        headerFixture()..['data'] = 'https://example.test/image.png',
        headerFixture()..['path'] = 'local.png',
        headerFixture()..['execute'] = 'launch',
        headerFixture()..['width'] = 3,
        headerFixture()..['width'] = 2.0,
        headerFixture()..['height'] = 0,
        headerFixture()..['width'] = 2049,
        headerFixture()..['data'] = base64Encode(Uint8List(16385)),
        headerFixture()..['data'] = base64Encode(Uint8List(45)),
        headerFixture()..['data'] = base64Encode(Uint8List(44)),
      ]) {
        expect(
          () => OverlayAppearanceConfiguration.fromMap(
            fixture()..['preview'] = source,
          ),
          throwsFormatException,
        );
      }
      final bytes = base64Decode(headerFixture()['data'] as String);
      ByteData.sublistView(bytes).setUint32(8, 12);
      expect(
        () => AppearanceBitmap.fromMap(
          headerFixture()..['data'] = base64Encode(bytes),
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'installed static poster keeps pixel filtering and never invents motion controls or substitutes another skin',
    (tester) async {
      size(tester, const Size(640, 400));
      final bytes = (await tester.runAsync(tinyPng))!;
      for (final previewable in [true, false]) {
        await tester.pumpWidget(
          app(
            OverlayAppearancePreview(
              appearanceId: 'FixtureInstalled',
              nativePoster: bytes,
              previewableIds: previewable
                  ? const {'FixtureInstalled'}
                  : const {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final image = find.byKey(
          const Key('overlay-native-preview-FixtureInstalled'),
        );
        expect(image, previewable ? findsOneWidget : findsNothing);
        if (previewable) {
          final widget = tester.widget<Image>(image);
          expect(widget.image, isA<MemoryImage>());
          expect(widget.filterQuality, FilterQuality.none);
        }
        expect(
          find.byKey(const Key('overlay-preview-motion-toggle')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('overlay-preview-browse-FixtureInstalled')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        app(
          const OverlayAppearancePreview(
            appearanceId: 'Missing',
            previewableIds: {'Missing'},
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
    },
  );

  if (installed != null) {
    testWidgets(
      'installed native poster decodes and renders without re-created art',
      (tester) async {
        size(tester, const Size(640, 400));
        final config = OverlayAppearanceConfiguration.fromMap(
          (jsonDecode(File(installed).readAsStringSync()) as Map)
              .cast<String, Object?>(),
        );
        final poster = config.preview!;
        await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(poster.bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, poster.width);
          expect(frame.image.height, poster.height);
          frame.image.dispose();
          codec.dispose();
        });
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 640,
                  child: OverlayAppearancePreview(
                    appearanceId: config.appearanceId,
                    previewableIds: {config.appearanceId},
                    nativePoster: poster.bytes,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await precacheImage(MemoryImage(poster.bytes), key.currentContext!);
        });
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('overlay-native-preview-${config.appearanceId}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (capture != null) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(capture).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
