import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';

import '../../app/menu_overlay/menu_reference_crop_test.dart' show pixels;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cn_visual_test.dart' as render;
import 'interaction_batch3cq_support.dart' as image;

Future<Uint8List> rgba(WidgetTester t, Uint8List png) async =>
    (await t.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return Uint8List.fromList(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }))!;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final configuration in [
      (900.0, 1.0, true),
      (392.0, 1.0, false),
      (344.0, 2.0, false),
    ]) {
      testWidgets(
        '$suite actual opacity width=${configuration.$1} text=${configuration.$2}',
        (t) async {
          size(t, Size(configuration.$1, 700));
          final png = await pixels(t);
          final calls = <String>[];
          final tools = image.owner(png, (name, args) async {
            calls.add(name);
            return png;
          })..referenceOpacity = .6;
          var reduce = false;
          late StateSetter update;
          final frame = GlobalKey();
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, state) {
                update = state;
                return scopedApp(
                  Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(configuration.$2),
                      ),
                      child: RepaintBoundary(
                        key: frame,
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: MenuImageTool(tools: tools),
                        ),
                      ),
                    ),
                  ),
                  suite,
                  light: configuration.$3,
                  reduce: reduce,
                );
              },
            ),
          );
          await image.cache(t, png);
          final slider = find.byType(StarBridgeSlider);
          await t.ensureVisible(slider);
          await t.pumpAndSettle();
          final directory = Directory('build/reviews/interaction-batch3cr')
            ..createSync(recursive: true);
          final name =
              'image-${suite.name}-${configuration.$1.toInt()}-${configuration.$2}';
          File('${directory.path}/$name-idle.png')
              .writeAsBytesSync(await render.pixels(t, find.byKey(frame)));
          final rect = t.getRect(slider);
          expect(rect.height, 48);
          final gesture = await t.startGesture(rect.center);
          await gesture.moveBy(const Offset(30, 0));
          await t.pump(const Duration(milliseconds: 30));
          await gesture.moveBy(const Offset(5, 0));
          await t.pump(const Duration(milliseconds: 30));
          File('${directory.path}/$name-active.png')
              .writeAsBytesSync(await render.pixels(t, find.byKey(frame)));
          final actual = tools.referenceOpacity;
          expect(actual, isNot(.6));
          update(() => reduce = true);
          await image.frames(t);
          final stable = await render.pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 90));
          final later = await render.pixels(t, find.byKey(frame));
          File('${directory.path}/$name-reduced.png').writeAsBytesSync(stable);
          File('${directory.path}/$name-reduced-later.png')
              .writeAsBytesSync(later);
          expect(
            listEquals(await rgba(t, later), await rgba(t, stable)),
            isTrue,
            reason: 'Full actual-view raw RGBA pixels must be static, independent of PNG encoding',
          );
          expect(tools.referenceOpacity, actual);
          File('${directory.path}/$name-reduced.png').writeAsBytesSync(stable);
          await gesture.up();
          await image.frames(t);
          expect(calls, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          tools.dispose();
        },
      );
    }
  }
}
