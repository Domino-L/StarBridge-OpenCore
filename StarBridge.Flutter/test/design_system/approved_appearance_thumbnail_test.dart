import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/approved_appearance_thumbnail.dart';

class PendingArtwork extends ImageProvider<PendingArtwork> {
  final result = Completer<ImageInfo>();
  int loads = 0;

  @override
  Future<PendingArtwork> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    PendingArtwork key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    return OneFrameImageStreamCompleter(result.future);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loading and failure remain local to the 34 DIP artwork', (
    tester,
  ) async {
    final provider = PendingArtwork();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ApprovedAppearanceThumbnail(
            skinId: 'Default',
            imageProvider: provider,
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSize(find.byType(ApprovedAppearanceThumbnail)),
      const Size(34, 34),
    );
    provider.result.completeError(StateError('fixture failure'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing appearance reuses the same pending atlas load', (
    tester,
  ) async {
    final provider = PendingArtwork();
    Widget app(String id) => MaterialApp(
      home: Center(
        child: ApprovedAppearanceThumbnail(skinId: id, imageProvider: provider),
      ),
    );
    await tester.pumpWidget(app('Default'));
    await tester.pumpWidget(app('NightShadow'));
    await tester.pumpWidget(app('Verdict'));
    expect(provider.loads, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test(
    'approved atlas is sampled at full resolution for all supported DPIs',
    () async {
      final file = File(ApprovedAppearanceThumbnail.assetPath);
      if (!file.existsSync()) return;
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      final atlas = frame.image;
      try {
        expect(atlas.width, 1774);
        expect(atlas.height, 887);
        for (final id in ApprovedAppearancePainter.regions.keys) {
          for (final dpr in [1, 2, 3, 4]) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)..scale(dpr.toDouble());
            ApprovedAppearancePainter(
              atlas: atlas,
              skinId: id,
            ).paint(canvas, const Size(34, 34));
            final picture = recorder.endRecording();
            final sampled = await picture.toImage(34 * dpr, 34 * dpr);
            final pixels = (await sampled.toByteData())!;
            expect(sampled.width, 34 * dpr);
            for (var index = 3; index < pixels.lengthInBytes; index += 4) {
              expect(
                pixels.getUint8(index),
                255,
                reason: '$id DPR $dpr remains opaque',
              );
            }
            sampled.dispose();
            picture.dispose();
          }
        }
      } finally {
        atlas.dispose();
        codec.dispose();
      }
    },
    skip: !File(ApprovedAppearanceThumbnail.assetPath).existsSync()
        ? 'Approved private acceptance artwork is not staged in public builds.'
        : false,
  );
}
