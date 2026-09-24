import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';

import 'all_catalog_motion_test.dart' as fixtures;

void main() {
  testWidgets(
    'every sequence paints changing vector frames without rebuilding',
    (tester) async {
      final samples = <int>[];
      final gallery = ui.PictureRecorder();
      final galleryCanvas = Canvas(gallery);
      var row = 0;
      for (final key in fixtures.motionKeys) {
        final motion = ValueNotifier(0.0);
        final animation = _Progress(motion);
        final base = fixtures.motionApp(key) as MaterialApp;
        var builds = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: base.theme,
            home: Builder(
              builder: (_) {
                builds++;
                return Center(
                  child: CatalogVehicleIcon.byKey(
                    iconKey: key,
                    motion: animation,
                  ),
                );
              },
            ),
          ),
        );
        final painter = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(CatalogVehicleIcon),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!;
        final frames = <List<int>>[];
        for (final progress in [.1, .3, .5, .7, .9]) {
          motion.value = progress;
          await tester.pump();
          final recorder = ui.PictureRecorder();
          final watch = Stopwatch()..start();
          painter.paint(Canvas(recorder), const Size(96, 96));
          samples.add(watch.elapsedMicroseconds);
          final picture = recorder.endRecording();
          frames.add(
            (await tester.runAsync(() async {
              final image = await picture.toImage(96, 96);
              final bytes = (await image.toByteData())!.buffer
                  .asUint8List()
                  .toList();
              image.dispose();
              return bytes;
            }))!,
          );
          picture.dispose();
          if (row % 6 == 0) {
            galleryCanvas.save();
            galleryCanvas.translate(
              (frames.length - 1) * 112.0,
              (row ~/ 6) * 112.0,
            );
            painter.paint(galleryCanvas, const Size(96, 96));
            galleryCanvas.restore();
          }
        }
        expect(
          frames.skip(1).any((frame) {
            for (var i = 0; i < frame.length; i++) {
              if (frame[i] != frames.first[i]) return true;
            }
            return false;
          }),
          isTrue,
          reason: '$key must change actual painted pixels',
        );
        expect(
          builds,
          1,
          reason: '$key must repaint without rebuilding the page',
        );
        await tester.pumpWidget(const SizedBox());
        motion.dispose();
        row++;
      }
      final picture = gallery.endRecording();
      if (Platform.environment['STARBRIDGE_MOTION_QA'] == '1') {
        await tester.runAsync(() async {
          final image = await picture.toImage(560, 784);
          final dir = Directory('build/local-integration/motion-qa')
            ..createSync(recursive: true);
          File('${dir.path}/sequence-samples.png').writeAsBytesSync(
            (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          image.dispose();
        });
      }
      picture.dispose();
      samples.sort();
      // Diagnostic only: debug widget tests are not release GPU performance proof.
      debugPrint(
        'Vector paint recording (debug, 210 samples): '
        'median=${samples[samples.length ~/ 2]}us '
        'p95=${samples[(samples.length * .95).floor()]}us max=${samples.last}us',
      );
    },
  );
}

class _Progress extends Animation<double> {
  _Progress(this.source);
  final ValueNotifier<double> source;
  @override
  double get value => source.value;
  @override
  AnimationStatus get status => AnimationStatus.forward;
  @override
  void addListener(VoidCallback listener) => source.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => source.removeListener(listener);
  @override
  void addStatusListener(AnimationStatusListener listener) {}
  @override
  void removeStatusListener(AnimationStatusListener listener) {}
}
