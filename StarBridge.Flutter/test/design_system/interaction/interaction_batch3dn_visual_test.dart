import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_page.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_waiting.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cn_visual_test.dart' show pixels;
import 'interaction_batch3dn_test.dart' show Tool, action, waitData;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/tools/exec_hangar_presets.dart';
import '../../features/tools/exec_hangar_test.dart' as original;

Future<void> capture(WidgetTester t, GlobalKey frame, String name) =>
    t.runAsync(() async {
      final image =
          await (frame.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final file = File('build/reviews/interaction-batch3dn/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
      } finally {
        image.dispose();
      }
    });

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final config =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets(
          '$config real tool waiting is visible, animated then live-reduced, failure retains fields',
          (t) async {
            final semantics = t.ensureSemantics();
            try {
              size(t, const Size(390, 800));
              t.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
              final port = Tool()..readGate = Completer(),
                  frame = GlobalKey(),
                  page = GlobalKey<ExecHangarPageState>();
              Widget host({bool reduce = false}) => RepaintBoundary(
                key: frame,
                child: scopedApp(
                  ExecHangarPage(key: page, port: port),
                  suite,
                  light: light,
                  reduce: reduce,
                ),
              );
              await t.pumpWidget(host());
              await t.pump(const Duration(milliseconds: 120));
              final waiting = find.byType(ExecHangarWaiting);
              Finder marker() => find.descendant(
                of: find.descendant(
                  of: waiting,
                  matching: find.byType(SocialReadActivity),
                ),
                matching: find.byType(RepaintBoundary),
              );
              expect(t.getSize(marker()).width, greaterThan(100));
              expect(t.getSize(marker()).height, 4);
              expect(waitData(t, waiting).reduceMotion, isFalse);
              final moving = await pixels(t, marker());
              await t.pump(const Duration(milliseconds: 190));
              expect(await pixels(t, marker()), isNot(orderedEquals(moving)));
              await capture(t, frame, '3dn-$config-initial-read');
              final node = t.getSemantics(waiting).getSemanticsData();
              expect(node.label, '读取机库时间…');
              expect(node.value, isEmpty);
              await t.pumpWidget(host(reduce: true));
              await t.pump();
              await t.pump();
              expect(waitData(t, waiting).reduceMotion, isTrue);
              final still = await pixels(t, marker());
              await t.pump(const Duration(milliseconds: 250));
              expect(await pixels(t, marker()), orderedEquals(still));
              await capture(t, frame, '3dn-$config-reduced-read');
              port.readGate!.complete(original.sample());
              await t.pumpAndSettle();
              expect(waiting, findsNothing);
              await t.pumpWidget(host());
              await t.pumpAndSettle();
              port.readGate = Completer();
              await action(t, 'exec-refresh', 'refresh', 'pointer');
              await t.pump(const Duration(milliseconds: 180));
              expect(
                t.widget<ExecHangarWaiting>(waiting).source,
                InteractionSource.pointer,
              );
              expect(t.widget<ExecHangarWaiting>(waiting).opening, isFalse);
              expect(waitData(t, waiting).reduceMotion, isFalse);
              await capture(t, frame, '3dn-$config-refresh');
              port.readGate!.completeError(StateError('synthetic offline'));
              await t.pumpAndSettle();
              expect(waiting, findsNothing);
              // The two lead-time preset lists keep their fields after a failed read.
              expect(execPreset(execBeforeOpen), findsOneWidget);
              expect(execPreset(execBeforeClose), findsOneWidget);
              expect(port.saves, 0);
              expect(port.commands, isEmpty);
              await capture(t, frame, '3dn-$config-refresh-failed');
              await t.pumpWidget(const SizedBox());
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
