import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_preview_stage.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3cd_test.dart'
    show Fixture, Harness, HarnessState, Picker, menus;
import 'interaction_batch3ca_test.dart' show key, fire;
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
    final file = File('build/reviews/interaction-batch3cd/$name.png');
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
      testWidgets(
        '$suite ${config.$1}/${config.$2} preview and failed-save review',
        (t) async {
          await loadFonts();
          viewport(t, config);
          final oldShadows = debugDisableShadows;
          debugDisableShadows = false;
          final h = Fixture(), boundary = GlobalKey(), picker = Picker();
          picker.install();
          try {
            await h.ready();
            await t.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: Harness(h, suite, stage: true),
              ),
            );
            final state = t.state<HarnessState>(find.byType(Harness));
            state.change(() => state.light = config.$1 > 1000);
            await frames(t);
            final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
            await key(t, 'pointer', 'overlay-preview-background');
            await t.pump(const Duration(milliseconds: 40));
            expect(
              t.widget<SuiteSurfaceTransition>(menus).animation.value,
              inExclusiveRange(0, 1),
            );
            await capture(t, boundary, '$name-background-enter');
            await frames(t);
            await capture(t, boundary, '$name-background-settled');
            picker.pending = Completer<String?>();
            await fire(
              t,
              'pointer',
              find.byKey(
                const ValueKey<Object>('overlay-preview-background-image'),
              ),
            );
            await t.pump(const Duration(milliseconds: 50));
            expect(find.byType(SuiteBusyLabel), findsOneWidget);
            await capture(t, boundary, '$name-image-wait');
            picker.fail = true;
            picker.pending!.complete(null);
            await frames(t);
            expect(find.byType(SnackBar), findsOneWidget);
            await capture(t, boundary, '$name-image-failed');
            ScaffoldMessenger.of(
              t.element(find.byType(OverlayWorkspacePreviewStage)),
            ).clearSnackBars();
            await frames(t);
            await h.dirtyFailure();
            await t.pumpWidget(
              RepaintBoundary(key: boundary, child: Harness(h, suite)),
            );
            await frames(t);
            // A failed save offers retry and discard on the banner.
            expect(
              find.byKey(const Key('overlay-workspace-discard-failed')),
              findsOneWidget,
            );
            await capture(t, boundary, '$name-save-failed');
            h.port.reject = false;
            await key(t, 'pointer', 'overlay-workspace-retry-failure');
            await frames(t);
            expect(h.module.projection.value.dirty, isFalse);
            await capture(t, boundary, '$name-save-retried');
          } finally {
            debugDisableShadows = oldShadows;
            await picker.clean(t);
            await h.clean(t);
          }
        },
      );
    }
  }
}
