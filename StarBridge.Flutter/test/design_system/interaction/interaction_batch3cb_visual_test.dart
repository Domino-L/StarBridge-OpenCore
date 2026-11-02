import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bz_test.dart' show FullFixture;
import 'interaction_batch3ca_test.dart'
    show MenuFixture, MenuHarness, MenuHarnessState, key;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3i_test.dart' show scopedApp;
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
    final file = File('build/reviews/interaction-batch3cb/$name.png');
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
    for (final config in [(430.0, 1.0), (1400.0, 1.0), (430.0, 2.0)]) {
      testWidgets(
        '$suite ${config.$1}/${config.$2} real menu exit and revival',
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
            final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
            await capture(t, boundary, '$name-menu-settled');
            await key(t, 'pointer', 'menu-workspace-discard');
            await t.pump(const Duration(milliseconds: 30));
            final a = t
                .widget<SuiteSurfaceTransition>(
                  find.byType(SuiteSurfaceTransition).first,
                )
                .animation;
            expect(a.status, AnimationStatus.reverse);
            expect(a.value, inExclusiveRange(0, 1));
            await capture(t, boundary, '$name-menu-exit');
            h.draft.change({'showClock': false});
            await t.pump();
            await frames(t);
            await capture(t, boundary, '$name-menu-revived');
          } finally {
            debugDisableShadows = oldShadows;
            await h.clean(t);
          }
        },
      );
    }
    testWidgets('$suite actual information saving status review', (t) async {
      await loadFonts();
      viewport(t, (1400, 1));
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      final h = FullFixture(), boundary = GlobalKey();
      try {
        await h.module.initialize();
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: scopedApp(OverlayWorkspacePage(module: h.module), suite),
          ),
        );
        await frames(t);
        h.port.pending = Completer<void>();
        h.module.updateSetting('showMembers', true);
        await frames(t);
        expect(find.text('正在保存更改…'), findsOneWidget);
        await capture(t, boundary, '${suite.name}-information-saving');
        h.port.pending!.complete();
        await frames(t);
        expect(find.text('已保存'), findsOneWidget);
        await capture(t, boundary, '${suite.name}-information-saved');
      } finally {
        debugDisableShadows = oldShadows;
        await h.clean(t);
      }
    });
  }
}
