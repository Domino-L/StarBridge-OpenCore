import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3cc_test.dart'
    show Fixture, MenuHarness, MenuHarnessState, menus, choose;
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
    final file = File('build/reviews/interaction-batch3cc/$name.png');
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
    for (final config in [
      (430.0, 1.0),
      (1100.0, 1.0),
      (430.0, 2.0),
      (320.0, 2.0),
    ]) {
      testWidgets('$suite ${config.$1}/${config.$2} selector and retry review', (
        t,
      ) async {
        await loadFonts();
        viewport(t, config);
        final oldShadows = debugDisableShadows;
        debugDisableShadows = false;
        final h = Fixture(), boundary = GlobalKey();
        try {
          await t.pumpWidget(
            RepaintBoundary(key: boundary, child: MenuHarness(h, suite)),
          );
          final state = t.state<MenuHarnessState>(find.byType(MenuHarness));
          state.change(() => state.light = config.$1 > 1000);
          await frames(t);
          final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
          await key(t, 'pointer', 'menu-workspace-section-command');
          await t.pump(const Duration(milliseconds: 40));
          expect(
            t.widget<SuiteSurfaceTransition>(menus).animation.value,
            inExclusiveRange(0, 1),
          );
          await capture(t, boundary, '$name-menu-enter');
          await frames(t);
          await capture(t, boundary, '$name-menu-settled');
          // Close first; choose exercises the actual trigger and new selection.
          await t.tapAt(Offset(config.$1 - 4, 990));
          await frames(t);
          await choose(t, 'pointer', 'browser');
          h.port.failRead = true;
          await h.draft.reload();
          await frames(t);
          await capture(t, boundary, '$name-failed-read');
          h.port.pending = Completer<void>();
          await key(t, 'pointer', 'menu-workspace-reload');
          await t.pump(const Duration(milliseconds: 70));
          expect(find.byType(SuiteBusyLabel), findsOneWidget);
          await capture(t, boundary, '$name-retry-wait');
        } finally {
          debugDisableShadows = oldShadows;
          await h.clean(t);
        }
      });
    }
  }
}
