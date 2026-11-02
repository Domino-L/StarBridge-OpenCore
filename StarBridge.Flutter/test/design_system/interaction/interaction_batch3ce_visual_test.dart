import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ce_test.dart' show Fixture, Harness, HarnessState;
import 'interaction_batch3ca_test.dart' show key;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () =>
        (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(),
  ))!;
  try {
    final bytes = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final file = File('build/reviews/interaction-batch3ce/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets('$suite $config leave confirmation review', (t) async {
        await loadFonts();
        viewport(t, config);
        final oldShadows = debugDisableShadows;
        debugDisableShadows = false;
        final f = Fixture(), boundary = GlobalKey();
        try {
          await f.ready(menuDirty: true, infoDirty: true);
          await t.pumpWidget(
            RepaintBoundary(key: boundary, child: Harness(f, suite)),
          );
          final state = t.state<HarnessState>(find.byType(Harness));
          state.change(() => state.light = config.$1 > 1000);
          await frames(t);
          final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
          await key(t, 'pointer', 'leave');
          await t.pump(const Duration(milliseconds: 60));
          await capture(t, boundary, '$name-menu-enter');
          await frames(t);
          await capture(t, boundary, '$name-menu-settled');
          await key(t, 'pointer', 'menu-unsaved-leave-save');
          await frames(t);
          await capture(t, boundary, '$name-memory-confirm');
          await key(t, 'keyboard', 'menu-clear-memory-confirm');
          await frames(t);
          await capture(t, boundary, '$name-information-keyboard');
          await key(t, 'keyboard', 'overlay-unsaved-leave-cancel');
          await frames(t);
          expect(f.result, false);
          expect(f.module.workspace!.projection.value.dirty, true);
          await key(t, 'pointer', 'leave');
          await frames(t);
          await capture(t, boundary, '$name-information-pointer');
          await key(t, 'keyboard', 'overlay-unsaved-leave-cancel');
          await frames(t);
        } finally {
          debugDisableShadows = oldShadows;
          await f.clean(t);
        }
      });
    }
  }
}
