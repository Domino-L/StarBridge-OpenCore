import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_holo_art.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF406080),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Set<int?> _decodeWidths(WidgetTester tester) => {
  for (final image in tester.widgetList<Image>(find.byType(Image)))
    image.image is ResizeImage ? (image.image as ResizeImage).width : null,
};

// 2026-10-28 user report: the community page stutters near the end of the
// upper/lower switch while the main fleet does not. The community banner is
// read bytes decoded at its shown size; while the deck collapses that size
// crossed several 256px buckets, and every crossing decoded the whole image
// again.
void main() {
  testWidgets('a shrinking banner keeps its decode instead of redoing it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = (await tester.runAsync(() => _png(3000, 1000)))!;
    final art = OrganizationHoloArt.bytes(bytes);
    var height = 800.0;
    late StateSetter resize;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              resize = setState;
              return SizedBox(width: 1600, height: height, child: art.image());
            },
          ),
        ),
      ),
    );
    // The header-only size read completes outside the fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final first = _decodeWidths(tester);
    expect(first, isNotEmpty);
    final seen = <int?>{...first};
    for (var h = 780.0; h >= 64; h -= 20) {
      resize(() => height = h);
      await tester.pump(const Duration(milliseconds: 16));
      seen.addAll(_decodeWidths(tester));
    }
    expect(seen, first, reason: 'Collapsing must not decode again.');
    // Growing past the largest shown size decodes once at the new size.
    resize(() => height = 1600);
    await tester.pump();
    expect(_decodeWidths(tester), isNot(first));
  });
}
