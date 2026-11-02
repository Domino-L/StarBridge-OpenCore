import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';

import '../official_fleet/official_fleet_hangar_sharing_test.dart' show host;

void main() {
  for (final (focus, expected) in const [
    (0.0, [255, 0, 0, 255]),
    (.5, [0, 255, 0, 255]),
    (1.0, [0, 0, 255, 255]),
  ]) {
    testWidgets(
      'common renderer shows authorized focal region $focus without changing artwork',
      (tester) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(i * 100, 0, 100, 100),
            Paint()
              ..color = const [
                Color(0xffff0000),
                Color(0xff00ff00),
                Color(0xff0000ff),
              ][i],
          );
        }
        final picture = recorder.endRecording();
        final image = (await tester.runAsync(() => picture.toImage(300, 100)))!;
        picture.dispose();
        addTearDown(image.dispose);
        await tester.pumpWidget(
          host(
            Center(
              child: RepaintBoundary(
                key: const Key('crop-boundary'),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: CommunityWorkspaceImage(
                    bytes: Uint8List.fromList([1]),
                    icon: StandardIconSemantic.brokenImage,
                    crop: (focusX: focus, focusY: .5, zoom: 1),
                    decoder: (_, _) async => image.clone(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('crop-boundary')),
        );
        await tester.runAsync(() async {
          final rendered = await boundary.toImage(pixelRatio: 1);
          final bytes = (await rendered.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final center = bytes.buffer.asUint8List().sublist(
            (50 * 100 + 50) * 4,
            (50 * 100 + 50) * 4 + 4,
          );
          expect(center, expected);
          rendered.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
