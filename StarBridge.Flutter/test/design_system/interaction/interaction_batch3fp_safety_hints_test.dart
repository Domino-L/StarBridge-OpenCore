import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/account/account_safety.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3bw_test.dart'
    show SafetyPort, safetyHome, frames, cleanSafety;
import 'interaction_batch3i_test.dart' show scopedApp;

final _directory = visualOutputDir(
  'interaction_motion_batch3fp_20261017',
  legacySubdirectory: 'review',
);
Finder get _close => find.byKey(const Key('account-safety-close'));
Finder get _hint =>
    find.ancestor(of: _close, matching: find.byType(StarBridgeTooltip)).first;
SuiteTooltipState _state(WidgetTester t) =>
    t.state(find.descendant(of: _hint, matching: find.byType(SuiteTooltip)));

class _Probe {
  _Probe(this.suite, {this.light = false});
  final InteractionSuite suite;
  final bool light;
  final port = SafetyPort();
  final capture = GlobalKey();
  bool reduce = false;
  late StateSetter update;
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, state) {
        update = state;
        final base = scopedApp(
          safetyHome(port),
          suite,
          light: light,
          reduce: reduce,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
}

Future<void> _mount(WidgetTester t, _Probe p) async {
  size(t, const Size(1000, 1000));
  await t.pumpWidget(p.app());
  await frames(t);
  await t.tap(find.byKey(const Key('safety-open')));
  await frames(t);
}

Future<List<int>> _pixels(WidgetTester t, _Probe p, {String? png}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      if (png != null) {
        await Directory(_directory).create(recursive: true);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_directory/$png.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List()
          .toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  testWidgets('3fp shared safety close hint wiring', (t) async {
    final p = _Probe(InteractionSuite.standard);
    try {
      await _mount(t, p);
      expect(_hint, findsOneWidget);
      expect(t.widget<StarBridgeTooltip>(_hint).message, '关闭');
      expect(t.widget<StarBridgeTooltip>(_hint).consumeEscape, isFalse);
    } finally {
      await cleanSafety(t, p.port);
    }
  });
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      testWidgets(
        '3fp $suite light=$light hover hint retains close owner and settles reduce',
        (t) async {
          final p = _Probe(suite, light: light);
          final semantics = t.ensureSemantics();
          final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
          try {
            await _mount(t, p);
            final rect = t.getRect(_close);
            await mouse.addPointer(location: const Offset(2, 2));
            await mouse.moveTo(t.getCenter(_close));
            await t.pump(const Duration(milliseconds: 500));
            await frames(t, 4);
            expect(_state(t).isShowing, isTrue);
            expect(p.port.reads, 1);
            expect(p.port.inputs, isEmpty);
            final nodes = exposedNodes(t)
                .where(
                  (n) =>
                      n.getSemanticsData().label == '关闭' &&
                      n.getSemanticsData().flagsCollection.isButton,
                )
                .toList();
            expect(nodes, hasLength(1));
            expect(
              nodes.single.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
            p.update(() => p.reduce = true);
            await t.pump();
            await t.pump();
            final before = await _pixels(
              t,
              p,
              png: suite == InteractionSuite.standard
                  ? null
                  : '${suite.name}-${light ? 'light' : 'dark'}-safety-hint',
            );
            await frames(t, 38);
            expect(await _pixels(t, p), before);
            expect(t.getRect(_close), rect);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
            expect(_close, findsNothing);
            expect(p.port.disposals, 1);
            expect(p.port.inputs, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await cleanSafety(t, p.port);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '3fp $suite touch hint does not close or submit and same Esc exits',
      (t) async {
        final p = _Probe(suite);
        try {
          await _mount(t, p);
          final touch = await t.startGesture(t.getCenter(_close));
          await t.pump(const Duration(milliseconds: 600));
          await frames(t, 4);
          expect(_state(t).isShowing, isTrue);
          await touch.up();
          await frames(t, 4);
          expect(_close, findsOneWidget);
          expect(p.port.inputs, isEmpty);
          expect(p.port.disposals, 0);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(_close, findsNothing);
          expect(p.port.disposals, 1);
        } finally {
          await cleanSafety(t, p.port);
        }
      },
    );
    testWidgets(
      '3fp $suite hint during pending read closes and ignores late reply',
      (t) async {
        final p = _Probe(suite);
        p.port.pendingRead = Completer<AccountSafetySnapshot>();
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await _mount(t, p);
          await mouse.addPointer(location: const Offset(2, 2));
          await mouse.moveTo(t.getCenter(_close));
          await t.pump(const Duration(milliseconds: 500));
          await frames(t, 4);
          expect(_state(t).isShowing, isTrue);
          expect(p.port.reads, 1);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(_close, findsNothing);
          expect(p.port.disposals, 1);
          p.port.pendingRead!.complete(p.port.snapshot);
          await frames(t);
          expect(_close, findsNothing);
          expect(p.port.reads, 1);
          expect(p.port.inputs, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await cleanSafety(t, p.port);
        }
      },
    );
  }
}
