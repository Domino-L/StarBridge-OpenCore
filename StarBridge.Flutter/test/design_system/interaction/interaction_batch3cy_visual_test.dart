import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cy_test.dart' show dock, openContext;

Finder menuSurface() => find.byWidgetPredicate(
  (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
);
Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3cy');
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
    for (final source in ['pointer', 'keyboard']) {
      for (final width in [320.0, 1600.0]) {
        testWidgets(
          '$suite $source $width real menu transition and live settings',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = Size(width, 1000);
            final boundary = GlobalKey();
            late StateSetter update;
            var style = suite, reduce = false;
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
                            data: MediaQuery.of(
                              context,
                            ).copyWith(textScaler: const TextScaler.linear(2)),
                            child: Center(
                              child: dock(toggle: (_) {}, recover: (_) {}),
                            ),
                          ),
                        ),
                        style,
                        reduce: reduce,
                      ),
                    );
                  },
                ),
              );
              await t.pumpAndSettle();
              expect(find.byType(Image), findsNWidgets(2));
              await t.runAsync(() async {
                await Future.wait(
                  t
                      .widgetList<Image>(find.byType(Image))
                      .map(
                        (image) => precacheImage(
                          image.image,
                          t.element(find.byType(Image).first),
                        ),
                      ),
                );
              });
              await t.pumpAndSettle();
              await openContext(t, source);
              expect(menuSurface(), findsOneWidget);
              final surface = t.widget<SuiteSurfaceTransition>(menuSurface());
              if (source == 'keyboard') {
                expect(surface.animation.value, 1);
              } else {
                expect(surface.animation.value, lessThan(1));
              }
              await t.pump(const Duration(milliseconds: 80));
              update(() {
                reduce = true;
                style = InteractionSuite.values[(suite.index + 1) % 4];
              });
              await t.pump();
              await t.pump();
              final current = t.widget<SuiteSurfaceTransition>(menuSurface());
              expect(current.animation.value, 1);
              expect(
                InteractionScope.of(t.element(menuSurface())).suite,
                style,
              );
              final rect = t.getRect(find.text('移回当前屏幕'));
              expect(rect.left, greaterThanOrEqualTo(8));
              expect(rect.right, lessThanOrEqualTo(width - 8));
              final name = '${suite.name}-$source-$width';
              await capture(t, boundary, '$name-before');
              final still = await pixels(t, boundary);
              await t.pump(const Duration(milliseconds: 60));
              final after = await pixels(t, boundary);
              await capture(t, boundary, '$name-after');
              expect(after, orderedEquals(still));
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pump();
              await t.pump();
              expect(menuSurface(), findsNothing);
              expect(t.takeException(), isNull);
            } finally {
              await detach(t);
              t.view.reset();
            }
          },
        );
      }
    }
  }
}
