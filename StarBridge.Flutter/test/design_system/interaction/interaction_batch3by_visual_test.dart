import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3by_test.dart' show MenuFixture, submenu;
import 'interaction_batch3bt_test.dart' show hit;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets('$suite width=${config.$1} text=${config.$2} cascade review', (
        t,
      ) async {
        await loadFonts();
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        t.view.physicalSize = Size(config.$1, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final h = MenuFixture(), capture = GlobalKey();
        try {
          final base = scopedApp(
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                height: 64,
                child: Row(mainAxisSize: MainAxisSize.min, children: [h.home]),
              ),
            ),
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
          await hit(t, 'pointer', 'account-identity-command');
          await frames(t);
          for (final phase in ['root', 'submenu']) {
            if (phase == 'submenu') await submenu(t);
            await frames(t);
            expect(t.takeException(), isNull);
            for (final surface
                in find.byType(SuiteSurfaceTransition).evaluate()) {
              final box = surface.renderObject! as RenderBox;
              final bounds = box.localToGlobal(Offset.zero) & box.size;
              expect(bounds.left, greaterThanOrEqualTo(7.9));
              expect(bounds.right, lessThanOrEqualTo(config.$1 - 7.9));
              expect(bounds.top, greaterThanOrEqualTo(7.9));
              expect(bounds.bottom, lessThanOrEqualTo(892.1));
            }
            final image = (await t.runAsync(
              () =>
                  (capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(),
            ))!;
            try {
              final bytes = (await t.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.png),
              ))!;
              final file = File(
                'build/reviews/interaction-batch3by/${suite.name}-${config.$1.toInt()}-${config.$2}-$phase.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
            }
          }
        } finally {
          debugDisableShadows = previousShadows;
          await h.clean(t);
        }
      });
    }
  }
}
