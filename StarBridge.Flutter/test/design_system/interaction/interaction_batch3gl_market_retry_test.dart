import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3b_test.dart' show exposedNodes;

final _review = visualOutputDir(
  'interaction_motion_batch3gl_20261017',
  legacySubdirectory: 'review-primary',
);
const _legacy = Key('legacy-retry-geometry');
final _action = find.byType(StarBridgeActionButton);
final _adapter = find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_MarketRetryAction',
);

class _Probe {
  _Probe(this.kind, this.suite, {this.light = false, this.scale = 1});
  final String kind;
  final InteractionSuite suite;
  bool light, reduce = false, enabled = true, visible = true;
  bool scoped = true;
  double scale;
  VisualDensity? density;
  MaterialTapTargetSize? tapTarget;
  int owner = 1;
  final calls = <(int, InteractionSource)>[];
  final capture = GlobalKey();
  late StateSetter update;
  final at = DateTime(2026, 10, 17, 12, 34);

  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final callbackOwner = owner;
        void retry() =>
            calls.add((callbackOwner, captureStarBridgeActivationSource()()));
        final base = scopedApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: SizedBox(
                width: 580,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (visible)
                      if (kind == 'stale')
                        MarketStale(at, retry: retry)
                      else
                        MarketNotice(
                          'Read failed — retained fixture',
                          retry: enabled ? retry : null,
                        ),
                    Offstage(
                      child: Align(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: TextButton(
                          key: _legacy,
                          onPressed: () {},
                          child: Text(marketText(context, 'retry')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          suite,
          light: light,
          reduce: reduce,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme!.copyWith(
            visualDensity: density,
            materialTapTargetSize: tapTarget,
          ),
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: scoped ? base.builder : null,
          home: base.home,
        );
      },
    ),
  );

  Future<void> mount(WidgetTester t, {double width = 1280}) async {
    size(t, Size(width, 850));
    await t.pumpWidget(app());
    await frames(t, 40);
  }
}

void geometry(WidgetTester t, InteractionSuite suite) {
  final legacy = find.byKey(_legacy, skipOffstage: false);
  // The same original outer target expectation remains strict. The private
  // adapter now includes the native-equivalent unpainted tap padding.
  expect(t.getSize(_adapter), t.getSize(legacy));
  final oldFace = find
      .descendant(
        of: legacy,
        matching: find.byType(Material, skipOffstage: false),
        skipOffstage: false,
      )
      .first;
  final newFace = suite == InteractionSuite.standard
      ? find.descendant(of: _action, matching: find.byType(Material)).first
      : find
            .descendant(of: _action, matching: find.byType(SuitePressable))
            .first;
  expect(t.getSize(newFace), t.getSize(oldFace));
  final oldText = find
      .descendant(
        of: legacy,
        matching: find.byType(Text, skipOffstage: false),
        skipOffstage: false,
      )
      .first;
  final newText = find
      .descendant(of: _action, matching: find.byType(Text))
      .first;
  expect(t.getSize(newText), t.getSize(oldText));
  expect(
    t.getTopLeft(newText) - t.getTopLeft(_adapter),
    t.getTopLeft(oldText) - t.getTopLeft(legacy),
  );
}

// Actual pointer, keyboard and semantics paths, without settling between
// actions: rapid active commands must not be suppressed or queued by feedback.
Future<void> fire(WidgetTester t, String source) async {
  if (source == 'pointer') {
    await t.tap(_action);
  } else if (source == 'keyboard') {
    final detector = find.descendant(
      of: _action,
      matching: find.byType(FocusableActionDetector),
    );
    final node = detector.evaluate().isNotEmpty
        ? t.widget<FocusableActionDetector>(detector.first).focusNode
        : t
              .widget<ButtonStyleButton>(
                find
                    .descendant(
                      of: _action,
                      matching: find.byWidgetPredicate(
                        (w) => w is ButtonStyleButton,
                      ),
                    )
                    .first,
              )
              .focusNode;
    node!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final semantic = find.descendant(
      of: _action,
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.onTap != null,
      ),
    );
    final node = t.getSemantics(semantic.first);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  }
  await t.pump(const Duration(milliseconds: 16));
}

Future<List<int>> _pixels(WidgetTester t, _Probe p, {bool save = false}) async {
  final rect = t.getRect(_action).inflate(5);
  return (await t.runAsync(() async {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(p.capture),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      if (save) {
        await Directory(_review).create(recursive: true);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File('$_review/${p.suite.name}-${p.kind}.png')
            .writeAsBytes(png.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      return <int>[
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + rect.left.ceil()) * 4,
            (y * image.width + rect.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['stale', 'notice']) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '3gl $suite $kind $source forwards every action and new owner',
          (t) async {
            final semantics = t.ensureSemantics();
            final p = _Probe(kind, suite);
            try {
              await p.mount(t);
              for (var i = 0; i < 3; i++) {
                await fire(t, source);
              }
              final origin = source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard;
              expect(p.calls, [(1, origin), (1, origin), (1, origin)]);
              p.update(() => p.owner = 2);
              await t.pump();
              await fire(t, source);
              expect(p.calls.last, (2, origin));
              expect(p.calls, hasLength(4));
              // The owner can remove the retry; the presentation owns no work.
              p.update(() {
                if (kind == 'notice') {
                  p.enabled = false;
                } else {
                  p.visible = false;
                }
              });
              await frames(t, 50);
              expect(_action, findsNothing);
              expect(p.calls, hasLength(4));
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              semantics.dispose();
            }
          },
        );
      }
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '3gl C $suite $kind Theme-only $source uses existing resolver',
          (t) async {
            final semantics = t.ensureSemantics();
            final p = _Probe(kind, suite)..scoped = false;
            try {
              await p.mount(t);
              expect(InteractionScope.maybeOf(t.element(_adapter)), isNull);
              geometry(t, suite);
              final origin = source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard;
              for (var i = 0; i < 3; i++) {
                await fire(t, source);
              }
              expect(p.calls, [(1, origin), (1, origin), (1, origin)]);
              p.update(() => p.reduce = true);
              await t.pump();
              await t.pump();
              final stopped = await _pixels(t, p);
              await frames(t, 38);
              expect(changed(stopped, await _pixels(t, p)), 0);
              await fire(t, source);
              expect(p.calls, hasLength(4));
              expect(p.calls.last, (1, origin));
              geometry(t, suite);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              semantics.dispose();
            }
          },
        );
      }
      for (final light in [false, true]) {
        for (final width in [1280.0, 900.0]) {
          testWidgets(
            '3gl $suite $kind native geometry light=$light width=$width',
            (t) async {
              final p = _Probe(
                kind,
                suite,
                light: light,
                scale: width == 900 ? 1.5 : 1,
              );
              await p.mount(t, width: width);
              geometry(t, suite);
              final ctx = t.element(_action);
              final caption = marketText(ctx, 'retry');
              expect(
                find.descendant(of: _action, matching: find.text(caption)),
                findsOneWidget,
              );
              if (kind == 'stale') {
                expect(find.text('12:34'), findsOneWidget);
                expect(
                  t.widget<Tooltip>(find.byType(Tooltip)).message,
                  p.at.toLocal().toString(),
                );
                expect(find.text(marketText(ctx, 'stale')), findsOneWidget);
              } else {
                expect(
                  find.text('Read failed — retained fixture'),
                  findsOneWidget,
                );
                expect(
                  find.text(marketText(ctx, 'failureHint')),
                  findsOneWidget,
                );
                final emptyHint = marketText(ctx, 'emptyHint');
                p.update(() => p.enabled = false);
                await t.pump();
                expect(find.text(emptyHint), findsOneWidget);
                expect(_action, findsNothing);
              }
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            },
          );
        }
      }
      testWidgets('3gl $suite $kind pointer feedback and live reduce settle', (
        t,
      ) async {
        final p = _Probe(
          kind,
          suite,
          light:
              suite == InteractionSuite.rail || suite == InteractionSuite.glow,
          scale: 1.5,
        );
        await p.mount(t, width: 900);
        final before = await _pixels(t, p);
        await fire(t, 'pointer');
        await frames(t, 3);
        expect(changed(before, await _pixels(t, p)), greaterThan(0));
        // Further rapid actions still have perceptible feedback, not a dead
        // continuous state. Every callback has already taken effect.
        await fire(t, 'pointer');
        await fire(t, 'pointer');
        expect(p.calls, hasLength(3));
        expect(changed(before, await _pixels(t, p)), greaterThan(0));
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        final rect = t.getRect(_action);
        final stopped = await _pixels(t, p, save: true);
        await frames(t, 38);
        expect(changed(stopped, await _pixels(t, p)), 0);
        expect(t.getRect(_action), rect);
        await fire(t, 'pointer');
        final reduced = await _pixels(t, p);
        await frames(t, 38);
        expect(changed(reduced, await _pixels(t, p)), 0);
        expect(p.calls, hasLength(4));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
      for (final source in ['keyboard', 'reader']) {
        testWidgets('3gl $suite $kind $source has no residual motion', (
          t,
        ) async {
          final semantics = t.ensureSemantics();
          final p = _Probe(kind, suite);
          try {
            await p.mount(t);
            await fire(t, source);
            await t.pump();
            final after = await _pixels(t, p);
            await frames(t, 38);
            expect(changed(after, await _pixels(t, p)), 0);
            expect(p.calls, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        });
      }
      for (final profile in [
        (VisualDensity.compact, MaterialTapTargetSize.padded),
        (VisualDensity.compact, MaterialTapTargetSize.shrinkWrap),
        (VisualDensity.standard, MaterialTapTargetSize.shrinkWrap),
      ]) {
        testWidgets(
          '3gl C $suite $kind density=${profile.$1} target=${profile.$2}',
          (t) async {
            final p = _Probe(kind, suite)
              ..density = profile.$1
              ..tapTarget = profile.$2;
            await p.mount(t);
            geometry(t, suite);
            await fire(t, 'pointer');
            expect(p.calls, [(1, InteractionSource.pointer)]);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
      testWidgets(
        '3gl C $suite $kind padding edges share one action and semantics',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = _Probe(kind, suite);
          try {
            await p.mount(t);
            geometry(t, suite);
            final rect = t.getRect(_adapter);
            await t.tapAt(Offset(rect.center.dx, rect.top + 1));
            await t.pump(const Duration(milliseconds: 16));
            await t.tapAt(Offset(rect.center.dx, rect.bottom - 1));
            await t.pump(const Duration(milliseconds: 16));
            expect(p.calls, [
              (1, InteractionSource.pointer),
              (1, InteractionSource.pointer),
            ]);
            await t.tapAt(Offset(rect.center.dx, rect.top - 1));
            await t.pump(const Duration(milliseconds: 16));
            expect(p.calls, hasLength(2));
            final nodes = exposedNodes(t)
                .where(
                  (node) =>
                      node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                )
                .toList();
            expect(nodes, hasLength(1));
            expect(nodes.single.rect.size, rect.size);
            p.update(() => p.reduce = true);
            await t.pump();
            await t.pump();
            await t.tapAt(Offset(rect.center.dx, rect.top + 1));
            await t.pump(const Duration(milliseconds: 16));
            expect(p.calls, hasLength(3));
            final stopped = await _pixels(t, p);
            await frames(t, 38);
            expect(changed(stopped, await _pixels(t, p)), 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
  }
}
