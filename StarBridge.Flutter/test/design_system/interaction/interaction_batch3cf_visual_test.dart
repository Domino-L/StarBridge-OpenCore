import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3cf_test.dart'
    show Fixture, Harness, HarnessState, activate;
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
    final file = File('build/reviews/interaction-batch3cf/$name.png');
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
      testWidgets('$suite $config staged and immediate tools review', (
        t,
      ) async {
        await loadFonts();
        viewport(t, config);
        final oldShadows = debugDisableShadows;
        debugDisableShadows = false;
        final f = Fixture(), boundary = GlobalKey();
        final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
        Future<void> show(String kind) async {
          await t.pumpWidget(
            RepaintBoundary(key: boundary, child: Harness(f, suite, kind)),
          );
          final h = t.state<HarnessState>(find.byType(Harness));
          h.change(() => h.light = config.$1 > 1000);
          await frames(t);
        }

        try {
          await f.ready();
          await show('staged-shortcut');
          await capture(t, boundary, '$name-staged-shortcut');
          await show('staged-resume');
          await activate(t, 'pointer', 'menu-browser-resume-toggle');
          await frames(t);
          await capture(t, boundary, '$name-staged-resume');
          await show('staged-directory');
          f.directory.cancel = true;
          f.directory.wait['draft'] = Completer();
          await activate(t, 'pointer', 'menu-screenshot-directory-choose');
          await t.pump(const Duration(milliseconds: 80));
          await capture(t, boundary, '$name-staged-directory-wait');
          f.directory.wait['draft']!.complete();
          await frames(t);
          f.directory.cancel = false;
          await show('directory');
          f.directory.wait['choose'] = Completer();
          f.directory.fail.add('choose');
          await activate(t, 'pointer', 'menu-screenshot-directory-choose');
          await t.pump(const Duration(milliseconds: 80));
          await capture(t, boundary, '$name-directory-wait');
          f.directory.wait['choose']!.complete();
          await frames(t);
          await capture(t, boundary, '$name-directory-failed');
          await show('resume');
          f.resume.wait['save'] = Completer();
          f.resume.fail.add('save');
          await activate(t, 'pointer', 'menu-browser-resume-toggle');
          await t.pump(const Duration(milliseconds: 80));
          await capture(t, boundary, '$name-resume-wait');
          f.resume.wait['save']!.complete();
          await frames(t);
          await capture(t, boundary, '$name-resume-failed');
          await show('shortcut');
          await activate(t, 'pointer', 'menu-shortcut-close');
          await frames(t);
          f.shortcut.wait['save'] = Completer();
          f.shortcut.fail.add('save');
          await activate(t, 'pointer', 'menu-shortcut-save');
          await t.pump(const Duration(milliseconds: 80));
          await capture(t, boundary, '$name-shortcut-wait');
          f.shortcut.wait['save']!.complete();
          await frames(t);
          await capture(t, boundary, '$name-shortcut-failed');
        } finally {
          debugDisableShadows = oldShadows;
          await f.clean(t);
        }
      });
    }
  }
}
