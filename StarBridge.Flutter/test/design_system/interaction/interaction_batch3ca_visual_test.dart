import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bz_test.dart' show FullFixture;
import 'interaction_batch3ca_test.dart'
    show
        EditorHarness,
        EditorHarnessState,
        MenuFixture,
        MenuHarness,
        MenuHarnessState,
        key;
import 'interaction_batch3bw_test.dart' show frames;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () => (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
        .toImage(),
  ))!;
  try {
    final bytes = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final file = File('build/reviews/interaction-batch3ca/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

void viewport(WidgetTester t, (double, double) config) {
  t.view.physicalSize = Size(config.$1, 1000);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = config.$2;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1400.0, 1.0), (430.0, 2.0)]) {
      testWidgets('$suite ${config.$1}/${config.$2} shared editor review', (
        t,
      ) async {
        await loadFonts();
        viewport(t, config);
        final oldShadows = debugDisableShadows;
        debugDisableShadows = false;
        final h = FullFixture(), boundary = GlobalKey();
        try {
          await h.module.initialize();
          await t.pumpWidget(
            RepaintBoundary(key: boundary, child: EditorHarness(h, suite)),
          );
          final state = t.state<EditorHarnessState>(find.byType(EditorHarness));
          state.change(() => state.light = config.$1 > 1000);
          h.editor.change(() => h.editor.snapToGrid = true);
          await frames(t);
          final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
          await capture(t, boundary, '$name-assists');
          // The edit starts saving on its own.
          h.port.pending = Completer<void>();
          h.port.reject = true;
          h.module.updateSetting('showMembers', true);
          await frames(t);
          await capture(t, boundary, '$name-saving');
          h.port.pending!.complete();
          await frames(t);
          await t.ensureVisible(
            find.byKey(const Key('overlay-layout-text-opacity-Members')),
          );
          await frames(t);
          await capture(t, boundary, '$name-inspector-draft-retained');
        } finally {
          debugDisableShadows = oldShadows;
          await h.clean(t);
        }
      });
      testWidgets(
        '$suite ${config.$1}/${config.$2} real menu confirmation review',
        (t) async {
          await loadFonts();
          viewport(t, config);
          final oldShadows = debugDisableShadows;
          debugDisableShadows = false;
          final h = MenuFixture(), boundary = GlobalKey();
          try {
            await h.load();
            await t.pumpWidget(
              RepaintBoundary(key: boundary, child: MenuHarness(h, suite)),
            );
            final state = t.state<MenuHarnessState>(find.byType(MenuHarness));
            state.change(() => state.light = config.$1 > 1000);
            await frames(t);
            await key(t, 'pointer', 'menu-workspace-save');
            await frames(t);
            await capture(
              t,
              boundary,
              '${suite.name}-${config.$1.toInt()}-${config.$2}-menu-confirm',
            );
            await key(t, 'keyboard', 'menu-clear-memory-cancel');
            await frames(t);
            expect(h.port.sources, isEmpty);
            expect(h.resume.sources, isEmpty);
          } finally {
            debugDisableShadows = oldShadows;
            await h.clean(t);
          }
        },
      );
    }
  }
}
