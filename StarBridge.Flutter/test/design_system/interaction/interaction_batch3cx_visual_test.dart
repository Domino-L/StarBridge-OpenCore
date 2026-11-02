import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cw_lifecycle_test.dart' show hover;
import 'interaction_batch3cx_test.dart' show fixture, target;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3cx');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final id in ['dock', 'friends', 'hangar']) {
      for (final width in [320.0, 1200.0]) {
        testWidgets('$suite $id $width actual hint layout and reduced pixels', (
          t,
        ) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = Size(width, 900);
          var reduce = false;
          late StateSetter update;
          final boundary = GlobalKey();
          final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return RepaintBoundary(
                    key: boundary,
                    child: host(
                      Builder(
                        builder: (context) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: const TextScaler.linear(2)),
                          child: Center(child: fixture(id)),
                        ),
                      ),
                      suite,
                      reduce: reduce,
                    ),
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            final before = t.getRect(target(id));
            await mouse.addPointer(location: Offset.zero);
            await hover(t, mouse, target(id));
            expect(t.getRect(target(id)), before);
            final hint = find.ancestor(
              of: target(id),
              matching: find.byType(SuiteTooltip),
            );
            expect(t.state<SuiteTooltipState>(hint).isShowing, isTrue);
            final message = t.widget<SuiteTooltip>(hint).message;
            final bubble = t.getRect(find.text(message).last);
            expect(bubble.left, greaterThanOrEqualTo(8));
            expect(bubble.right, lessThanOrEqualTo(width - 8));
            expect(bubble.top, greaterThanOrEqualTo(8));
            expect(bubble.bottom, lessThanOrEqualTo(892));
            await capture(t, boundary, '${suite.name}-$id-$width');
            update(() => reduce = true);
            await t.pump();
            await t.pump();
            final still = await pixels(t, boundary);
            await t.pump(const Duration(milliseconds: 80));
            expect(await pixels(t, boundary), orderedEquals(still));
            expect(t.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await detach(t);
            t.view.reset();
          }
        });
      }
    }
  }
}
