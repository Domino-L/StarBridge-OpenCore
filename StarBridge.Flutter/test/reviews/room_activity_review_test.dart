import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  testWidgets('unified inbox renders at the supported compact width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    final composition = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('activity-review'),
        child: StarBridgeApp(composition: composition),
      ),
    );
    await tester.pumpAndSettle();
    await composition.partyRooms.selectPreviewScene('host');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('通知'));
    await tester.pumpAndSettle();
    expect(find.text('通知中心'), findsOneWidget);
    expect(find.text('房间提醒'), findsNothing);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('ROOM_REVIEW_PNG')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('activity-review')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/room-activity-review.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
