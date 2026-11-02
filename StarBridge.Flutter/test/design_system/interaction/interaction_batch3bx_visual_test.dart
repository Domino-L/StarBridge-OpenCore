import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bt_test.dart' show hit;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3bx_test.dart' show UpdateBridge, prepared;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets('$suite width=${config.$1} text=${config.$2} update review', (
        t,
      ) async {
        await loadFonts();
        t.view.physicalSize = Size(config.$1, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final h = UpdateBridge(), capture = GlobalKey();
        try {
          final base = scopedApp(
            h.home(),
            suite,
            light: config.$1 > 1000,
          ) as MaterialApp;
          await t.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: base.theme,
                themeAnimationDuration: Duration.zero,
                locale: base.locale,
                supportedLocales: base.supportedLocales,
                localizationsDelegates: base.localizationsDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(config.$2)),
                  child: base.builder!(context, child),
                ),
                home: base.home,
              ),
            ),
          );
          await t.pumpAndSettle();
          await hit(t, 'pointer', 'update-open');
          await frames(t);
          for (final phase in [
            'available',
            'unknown-size',
            'progress',
            'ready',
          ]) {
            if (phase == 'unknown-size') {
              await hit(t, 'pointer', 'update-download');
              await frames(t);
              await h.progress(
                h.last('applicationUpdates.prepare'),
                1048576,
                null,
              );
            } else if (phase == 'progress') {
              await h.progress(
                h.last('applicationUpdates.prepare'),
                1048576,
                2097152,
              );
            } else if (phase == 'ready') {
              await h.reply(h.last('applicationUpdates.prepare'), prepared());
            }
            await frames(t);
            expect(t.takeException(), isNull);
            final image = (await t.runAsync(
              () =>
                  (capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(),
            ))!;
            try {
              final data = (await t.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.png),
              ))!;
              final file = File(
                'build/reviews/interaction-batch3bx/${suite.name}-${config.$1.toInt()}-${config.$2}-$phase.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
            } finally {
              image.dispose();
            }
          }
        } finally {
          await h.clean(t);
        }
      });
    }
  }
}
