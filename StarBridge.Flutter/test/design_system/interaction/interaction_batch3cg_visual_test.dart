import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3cg_test.dart'
    show
        LivePort,
        Harness,
        HarnessState,
        ActionHarness,
        ActionState,
        activate,
        close;

Future<Uint8List> capture(
  WidgetTester t,
  GlobalKey boundary,
  String name,
) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () =>
        (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(),
  ))!;
  try {
    final data = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final file = File('build/reviews/interaction-batch3cg/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return bytes;
  } finally {
    image.dispose();
  }
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets('$suite $config actual live entry and local tools', (
        t,
      ) async {
        await loadFonts();
        viewport(t, config);
        final oldShadows = debugDisableShadows;
        debugDisableShadows = false;
        final port = LivePort(), boundary = GlobalKey();
        final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
        Future<HarnessState> show({bool local = false}) async {
          await t.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: Harness(port, suite, key: ValueKey(local), local: local),
            ),
          );
          final h = t.state<HarnessState>(find.byType(Harness));
          h.change(() => h.light = config.$1 > 1000);
          await frames(t);
          return h;
        }

        try {
          final h = await show();
          await capture(t, boundary, '$name-live-idle');
          await activate(t, 'pointer', 'menu-overlay-open-live');
          await t.pump(const Duration(milliseconds: 80));
          await capture(t, boundary, '$name-live-wait');
          h.change(() => h.reduce = true);
          await t.pump();
          await t.pump();
          await capture(t, boundary, '$name-live-static-wait');
          port.pending.single.complete(false);
          await frames(t);
          await capture(t, boundary, '$name-live-failed');
          await show(local: true);
          await activate(t, 'pointer', 'menu-local-snap');
          await frames(t);
          await capture(t, boundary, '$name-local-selected');
          await t.ensureVisible(find.byKey(const Key('menu-local-dimming')));
          await frames(t);
          await capture(t, boundary, '$name-local-dimming');
        } finally {
          debugDisableShadows = oldShadows;
          await close(t, [port]);
        }
      });
    }
    testWidgets('$suite every rapid pointer press has a visible response', (
      t,
    ) async {
      await loadFonts();
      viewport(t, (430.0, 1.0));
      final boundary = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(key: boundary, child: ActionHarness(suite)),
      );
      final h = t.state<ActionState>(find.byType(ActionHarness));
      await frames(t);
      final target = find.byKey(const Key('shared'));
      for (var i = 0; i < 6; i++) {
        final before = await capture(
          t,
          boundary,
          '${suite.name}-rapid-$i-before',
        );
        final g = await t.startGesture(t.getCenter(target));
        await t.pump(const Duration(milliseconds: 110));
        final pressed = await capture(
          t,
          boundary,
          '${suite.name}-rapid-$i-pressed',
        );
        if (suite != InteractionSuite.standard) {
          expect(
            listEquals(before, pressed),
            false,
            reason: 'Press $i must be visible',
          );
        }
        await g.up();
        // Start the reverse ticker before advancing elapsed time. A single
        // long pump only supplies its initial frame in this test binding.
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
      }
      expect(h.sources, List.filled(6, InteractionSource.pointer));
      await frames(t);
      await t.pumpWidget(const SizedBox());
    });
    for (final input in ['keyboard', 'reader', 'reduce']) {
      testWidgets('$suite $input has no transient animation tail', (t) async {
        final semantics = t.ensureSemantics();
        try {
          await loadFonts();
          viewport(t, (430.0, 1.0));
          final boundary = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(key: boundary, child: ActionHarness(suite)),
          );
          final h = t.state<ActionState>(find.byType(ActionHarness));
          if (input == 'reduce') h.change(() => h.reduce = true);
          await frames(t);
          await activate(t, input == 'reduce' ? 'pointer' : input, 'shared');
          await t.pump();
          await t.pump();
          final first = await capture(
            t,
            boundary,
            '${suite.name}-$input-first',
          );
          await t.pump(const Duration(milliseconds: 400));
          final last = await capture(t, boundary, '${suite.name}-$input-last');
          expect(listEquals(first, last), true);
          expect(h.sources, [
            input == 'reduce'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          ]);
        } finally {
          semantics.dispose();
          await t.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
