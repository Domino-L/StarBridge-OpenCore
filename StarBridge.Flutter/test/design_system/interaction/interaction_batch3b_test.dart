import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show SemanticsNode, RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_picker.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app;
import '../../features/friends/social_layout_test.dart' show loadFonts;

const trigger = Key('menu-trigger');
final surface = find.byType(SuiteSurfaceTransition);

class Probe {
  late MenuController controller;
  late FocusNode anchor;
  late ValueChanged<InteractionSource> toggle;
  int opened = 0, closed = 0;
  final calls = <(Object, InteractionSource)>[];
  List<StarBridgeMenuEntry> entries([
    List<String> ids = const ['a', 'disabled', 'b'],
  ]) => [
    for (final id in ids)
      StarBridgeMenuEntry(
        id: id,
        label: 'Choice $id',
        child: Text('Choice $id', maxLines: 1, overflow: TextOverflow.ellipsis),
        onActivate: id == 'disabled'
            ? null
            : (source) => calls.add((id, source)),
      ),
  ];
  Widget menu({
    List<StarBridgeMenuEntry>? entries,
    bool enabled = true,
  }) => NativeViewportMenu(
    builder: (onOpen, onClose) => StarBridgeMenuAnchor(
      entries: entries ?? this.entries(),
      enabled: enabled,
      semanticLabel: 'Source menu',
      onOpen: () {
        opened++;
        onOpen();
      },
      onClose: () {
        closed++;
        onClose();
      },
      // The existing custom shell trigger is a Material button too. The
      // menu's explicit semantic/keyboard paths must not depend on migrating
      // that button into a SuitePressable.
      builder: (context, controller, focus, toggle) {
        this.controller = controller;
        anchor = focus;
        this.toggle = toggle;
        return OutlinedButton(
          key: trigger,
          focusNode: focus,
          onPressed: enabled ? () => toggle(InteractionSource.pointer) : null,
          child: const Text('Source menu'),
        );
      },
    ),
  );
}

Future<void> semanticTap(WidgetTester tester, Finder target) async {
  final node = tester.getSemantics(target);
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
}

List<SemanticsNode> exposedNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    // Merged descendants are internal data of their exposed ancestor, not
    // additional platform-accessible controls.
    if (node.isMergedIntoParent) return;
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3B'] != '1') return;
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final directory = Directory('build/reviews/interaction-batch3b');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

FocusNode rowFocus(WidgetTester tester, String id, InteractionSuite suite) =>
    suite == InteractionSuite.standard
    ? tester.widget<MenuItemButton>(find.byKey(ValueKey<Object>(id))).focusNode!
    : tester
          .widget<SuitePressable>(find.byKey(ValueKey<Object>(id)))
          .focusNode!;

Future<void> open(WidgetTester tester, Probe probe, String source) async {
  if (source == 'pointer') {
    await tester.tap(find.byKey(trigger));
  } else if (source == 'reader') {
    await semanticTap(tester, find.byKey(trigger));
  } else {
    probe.anchor.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite actual custom trigger opens/closes as $source', (
        tester,
      ) async {
        final probe = Probe();
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(app(probe.menu(), suite: suite));
          await tester.pumpAndSettle();
          await open(tester, probe, source);
          expect(surface, findsOneWidget);
          final animation = tester
              .widget<SuiteSurfaceTransition>(surface)
              .animation;
          expect(
            animation.value,
            source == 'pointer' ? inExclusiveRange(0, 1) : 1,
          );
          expect(nativeViewportMenus.value, 1);
          expect(probe.opened, 1);
          if (source != 'pointer') {
            expect(rowFocus(tester, 'a', suite).hasFocus, isTrue);
          }
          final disabled = tester.getSemantics(
            find.byKey(const ValueKey<Object>('disabled')),
          );
          expect(
            disabled.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
          );
          await tester.pumpAndSettle();
          if (source == 'pointer') {
            await tester.tap(find.byKey(trigger));
          } else if (source == 'reader') {
            await semanticTap(tester, find.byKey(trigger));
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          }
          await tester.pump();
          await tester.pump();
          if (source == 'pointer') {
            expect(surface, findsOneWidget);
            expect(nativeViewportMenus.value, 1);
            // A RenderSemantics node can remain cached on an excluded widget;
            // only the owner-root tree is actually exposed to assistive tools.
            expect(
              exposedNodes(tester)
                  .where((node) => node.getSemanticsData().label == 'Choice a'),
              isEmpty,
            );
            expect(rowFocus(tester, 'a', suite).canRequestFocus, isFalse);
            await tester.pump(const Duration(milliseconds: 40));
            expect(surface, findsOneWidget);
            await tester.pumpAndSettle();
          }
          expect(surface, findsNothing);
          expect(nativeViewportMenus.value, 0);
          expect(probe.closed, 1);
          expect(probe.anchor.hasFocus, isTrue);
          expect(probe.calls, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });

      testWidgets(
        '$suite row $source selects exactly once and preserves source',
        (tester) async {
          final probe = Probe();
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(app(probe.menu(), suite: suite));
            await tester.pumpAndSettle();
            await open(tester, probe, source);
            await tester.pumpAndSettle();
            if (source == 'pointer') {
              await tester.tap(find.byKey(const ValueKey<Object>('b')));
              // Material's menu item dispatches post-frame, as before.
              await tester.pump();
            } else if (source == 'reader') {
              await semanticTap(
                tester,
                find.byKey(const ValueKey<Object>('b')),
              );
            } else {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pump();
              expect(rowFocus(tester, 'b', suite).hasFocus, isTrue);
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            }
            expect(probe.calls, [
              (
                'b',
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            await tester.pumpAndSettle();
            expect(nativeViewportMenus.value, 0);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite reopening during exit retains one overlay and reverses in place',
      (tester) async {
        final probe = Probe();
        await tester.pumpWidget(app(probe.menu(), suite: suite));
        await tester.pumpAndSettle();
        await open(tester, probe, 'pointer');
        await tester.pumpAndSettle();
        probe.toggle(InteractionSource.pointer);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 35));
        final animation = tester
            .widget<SuiteSurfaceTransition>(surface)
            .animation;
        final reversingValue = animation.value;
        expect(reversingValue, inExclusiveRange(0, 1));
        probe.toggle(InteractionSource.pointer);
        expect(animation.value, reversingValue);
        await tester.pumpAndSettle();
        expect(surface, findsOneWidget);
        expect(animation.value, 1);
        expect(nativeViewportMenus.value, 1);
        expect(probe.opened, 1);
        expect(probe.closed, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(surface, findsNothing);
        expect(nativeViewportMenus.value, 0);
        expect(tester.takeException(), isNull);
      },
    );

    for (final duringExit in [false, true]) {
      testWidgets(
        '$suite live local reduce/theme settles menu exit=$duringExit in two frames',
        (tester) async {
          final probe = Probe();
          Widget content(bool reduce) => MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: reduce,
            ),
            child: probe.menu(),
          );
          await tester.pumpWidget(app(content(false), suite: suite));
          await tester.pumpAndSettle();
          await open(tester, probe, 'pointer');
          if (duringExit) {
            await tester.pumpAndSettle();
            probe.toggle(InteractionSource.pointer);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 30));
          }
          await tester.pumpWidget(
            app(content(true), suite: suite, light: true),
          );
          await tester.pump();
          if (duringExit) {
            expect(surface, findsNothing);
            expect(nativeViewportMenus.value, 0);
          } else {
            final transition = tester.widget<SuiteSurfaceTransition>(surface);
            expect(transition.animation.value, 1);
            final data = InteractionScope.of(tester.element(surface));
            expect(data.reduceMotion, isTrue);
            expect(data.palette.isDark, isFalse);
            expect(transition.animation.isAnimating, isFalse);
            probe.toggle(InteractionSource.pointer);
            await tester.pump();
            await tester.pump();
            expect(surface, findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite removed/reordered/disabled focused rows repair by stable identity',
      (tester) async {
        final probe = Probe();
        await tester.pumpWidget(app(probe.menu(), suite: suite));
        await tester.pumpAndSettle();
        await open(tester, probe, 'keyboard');
        final originalB = rowFocus(tester, 'b', suite);
        await tester.pumpWidget(
          app(probe.menu(entries: probe.entries(['b', 'a'])), suite: suite),
        );
        await tester.pump();
        expect(rowFocus(tester, 'b', suite), same(originalB));
        expect(rowFocus(tester, 'a', suite).hasFocus, isTrue);
        await tester.pumpWidget(
          app(
            probe.menu(entries: probe.entries(['b', 'disabled'])),
            suite: suite,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(rowFocus(tester, 'b', suite).hasFocus, isTrue);
        await tester.pumpWidget(
          app(probe.menu(entries: probe.entries(['disabled'])), suite: suite),
        );
        await tester.pump();
        await tester.pump();
        expect(probe.anchor.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(probe.calls, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite exit caches old rows even if owner clears options and disables trigger',
      (tester) async {
        final probe = Probe();
        await tester.pumpWidget(app(probe.menu(), suite: suite));
        await tester.pumpAndSettle();
        await open(tester, probe, 'pointer');
        await tester.pumpAndSettle();
        probe.toggle(InteractionSource.pointer);
        await tester.pump();
        await tester.pumpWidget(
          app(probe.menu(entries: [], enabled: false), suite: suite),
        );
        expect(find.text('Choice a'), findsOneWidget);
        expect(nativeViewportMenus.value, 1);
        await tester.tap(
          find.byKey(const ValueKey<Object>('a')),
          warnIfMissed: false,
        );
        expect(probe.calls, isEmpty);
        await tester.pumpAndSettle();
        expect(surface, findsNothing);
        expect(nativeViewportMenus.value, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite outside tap reaches original target and disposal balances native viewport',
      (tester) async {
        final probe = Probe();
        var outside = 0;
        await tester.pumpWidget(
          app(
            Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => outside++,
                    behavior: HitTestBehavior.opaque,
                  ),
                ),
                Align(child: probe.menu()),
              ],
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        await open(tester, probe, 'pointer');
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(15, 15));
        expect(outside, 1);
        await tester.pump();
        expect(nativeViewportMenus.value, 1);
        await tester.pumpWidget(const SizedBox());
        expect(nativeViewportMenus.value, 0);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    for (final edge in [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ]) {
      for (final rtl in [false, true]) {
        testWidgets(
          '$suite window edge $edge rtl=$rtl 200% text stays inside and scrolls',
          (tester) async {
            final probe = Probe();
            final entries = [
              for (var i = 0; i < 12; i++)
                StarBridgeMenuEntry(
                  id: 'long-$i',
                  label: 'Long organization $i',
                  child: Text(
                    'Long organization $i ${'name ' * 20}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onActivate: (_) {},
                ),
            ];
            final menu = MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 600),
                textScaler: TextScaler.linear(2),
              ),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: SizedBox.expand(
                  child: Align(
                    alignment: edge,
                    child: probe.menu(entries: entries),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(app(menu, suite: suite));
            await tester.pumpAndSettle();
            await open(tester, probe, 'keyboard');
            await tester.pumpAndSettle();
            final rect = tester.getRect(surface);
            expect(rect.left, greaterThanOrEqualTo(8));
            expect(rect.top, greaterThanOrEqualTo(8));
            expect(rect.right, lessThanOrEqualTo(792));
            expect(rect.bottom, lessThanOrEqualTo(592));
            final scroll = tester.widget<Scrollable>(
              find
                  .descendant(of: surface, matching: find.byType(Scrollable))
                  .first,
            );
            expect(scroll.axisDirection, AxisDirection.down);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(nativeViewportMenus.value, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      '$suite Tab cycles enabled menu rows and keyboard scroll reveals last row',
      (tester) async {
        final probe = Probe();
        await tester.pumpWidget(app(probe.menu(), suite: suite));
        await tester.pumpAndSettle();
        await open(tester, probe, 'keyboard');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(rowFocus(tester, 'b', suite).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(rowFocus(tester, 'a', suite).hasFocus, isTrue);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(rowFocus(tester, 'b', suite).hasFocus, isTrue);
        await tester.pumpWidget(
          app(
            probe.menu(
              entries: probe.entries([for (var i = 0; i < 20; i++) 'item-$i']),
            ),
            suite: suite,
          ),
        );
        await tester.pump();
        await tester.pump();
        for (var i = 0; i < 19; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
        }
        final last = find.byKey(const ValueKey<Object>('item-19'));
        expect(rowFocus(tester, 'item-19', suite).hasFocus, isTrue);
        expect(
          tester.getRect(surface).contains(tester.getCenter(last)),
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite changing style while open preserves overlay, focus and latest row',
      (tester) async {
        final probe = Probe();
        await tester.pumpWidget(app(probe.menu(), suite: suite));
        await tester.pumpAndSettle();
        await open(tester, probe, 'keyboard');
        final next = InteractionSuite
            .values[(suite.index + 1) % InteractionSuite.values.length];
        final focus = rowFocus(tester, 'a', suite);
        await tester.pumpWidget(app(probe.menu(), suite: next));
        await tester.pumpAndSettle();
        expect(rowFocus(tester, 'a', next), same(focus));
        expect(focus.hasFocus, isTrue);
        expect(InteractionScope.of(tester.element(surface)).suite, next);
        expect(probe.opened, 1);
        expect(probe.closed, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(probe.calls, [('a', InteractionSource.keyboard)]);
        await tester.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite actual picker enter/settled/exit frames retain product menu content',
      (tester) async {
        final port = ScenePort();
        final owner = OverlaySceneController(port, autoStart: false);
        addTearDown(owner.dispose);
        await owner.refresh();
        final boundary = GlobalKey();
        if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3B'] == '1') {
          await loadFonts();
        }
        final template = app(
          OverlayScenePicker(controller: owner),
          suite: suite,
        ) as MaterialApp;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: template.theme,
              themeAnimationDuration: template.themeAnimationDuration,
              locale: template.locale,
              supportedLocales: template.supportedLocales,
              localizationsDelegates: template.localizationsDelegates,
              home: template.home,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('overlay-source-picker')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        await capture(tester, boundary, '${suite.name}-enter');
        await tester.pumpAndSettle();
        await capture(tester, boundary, '${suite.name}-settled');
        await tester.tap(find.byKey(const Key('overlay-source-picker')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          find.byKey(const ValueKey<Object>('overlay-source-org:B')),
          findsOneWidget,
        );
        await capture(tester, boundary, '${suite.name}-exit');
        await tester.pumpAndSettle();
        expect(port.writes, 0);
        expect(nativeViewportMenus.value, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite active repeated selections retain every entrance and callback',
      (tester) async {
        final probe = Probe();
        await tester.pumpWidget(app(probe.menu(), suite: suite));
        await tester.pumpAndSettle();
        for (var i = 0; i < 6; i++) {
          await open(tester, probe, 'pointer');
          final animation = tester
              .widget<SuiteSurfaceTransition>(surface)
              .animation;
          expect(animation.value, inExclusiveRange(0, 1));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey<Object>('a')));
          await tester.pump();
          expect(probe.calls.length, i + 1);
          expect(nativeViewportMenus.value, 1);
          await tester.pumpAndSettle();
          expect(nativeViewportMenus.value, 0);
        }
        expect(
          probe.calls.every((e) => e.$2 == InteractionSource.pointer),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite disabled trigger has no pointer, keyboard or reader open path',
      (tester) async {
        final probe = Probe();
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            app(probe.menu(enabled: false), suite: suite),
          );
          await tester.pumpAndSettle();
          final data = tester
              .getSemantics(find.byKey(trigger))
              .getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isFalse);
          await tester.tap(find.byKey(trigger), warnIfMissed: false);
          probe.toggle(InteractionSource.keyboard);
          await tester.pump();
          expect(surface, findsNothing);
          expect(nativeViewportMenus.value, 0);
          expect(probe.opened, 0);
          expect(probe.calls, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '$suite empty menu has safe keyboard escape and no phantom actions',
      (tester) async {
        final probe = Probe();
        await tester.pumpWidget(app(probe.menu(entries: []), suite: suite));
        await tester.pumpAndSettle();
        await open(tester, probe, 'keyboard');
        expect(probe.anchor.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(surface, findsNothing);
        expect(probe.calls, isEmpty);
        expect(nativeViewportMenus.value, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite actual pending picker invalidation removes old content and ignores stale answer',
      (tester) async {
        final port = ScenePort();
        final owner = OverlaySceneController(port, autoStart: false);
        addTearDown(owner.dispose);
        await owner.refresh();
        await tester.pumpWidget(
          app(OverlayScenePicker(controller: owner), suite: suite),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('overlay-source-picker')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<Object>('overlay-source-org:B')),
        );
        await tester.pump();
        expect(port.writes, 1);
        port.state = const OverlaySceneState(status: 'signedOut');
        port.events.add(null);
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(surface, findsNothing);
        expect(nativeViewportMenus.value, 0);
        expect(find.text('Beta'), findsNothing);
        port.pending.complete(
          const OverlaySceneState(
            revision: 8,
            mode: 'community',
            code: 'B',
            available: true,
            targets: targets,
          ),
        );
        await tester.pumpAndSettle();
        expect(owner.projection.value.status, 'signedOut');
        expect(owner.projection.value.code, isNull);
        expect(port.writes, 1);
        expect(tester.takeException(), isNull);
      },
    );

    for (final outcome in ['success', 'failure', 'leave']) {
      testWidgets(
        '$suite actual picker pending $outcome preserves unique owner and no replay',
        (tester) async {
          final port = ScenePort();
          final owner = OverlaySceneController(port, autoStart: false);
          addTearDown(owner.dispose);
          await owner.refresh();
          await tester.pumpWidget(
            app(OverlayScenePicker(controller: owner), suite: suite),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('overlay-source-picker')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey<Object>('overlay-source-org:B')),
          );
          await tester.pump();
          expect(port.writes, 1);
          expect(port.arguments, [(7, 'community', 'B')]);
          expect(owner.projection.value.busy, isTrue);
          expect(owner.projection.value.preferredId, 'org:A');
          await tester.tap(
            find.byKey(const Key('overlay-source-picker')),
            warnIfMissed: false,
          );
          await tester.pump();
          expect(port.writes, 1);
          if (outcome == 'leave') await tester.pumpWidget(const SizedBox());
          if (outcome == 'failure') {
            port.pending.completeError(StateError('local save rejected'));
          } else {
            port.state = const OverlaySceneState(
              revision: 8,
              mode: 'community',
              code: 'B',
              actualId: 'room',
              available: true,
              status: 'standby',
              targets: targets,
            );
            port.pending.complete(port.state);
          }
          await tester.pumpAndSettle();
          expect(port.writes, 1);
          expect(port.closed, isFalse);
          expect(owner.projection.value.busy, isFalse);
          expect(
            owner.projection.value.preferredId,
            outcome == 'failure' ? 'org:A' : 'org:B',
          );
          expect(owner.projection.value.actualId, 'room');
          if (outcome == 'leave') {
            await tester.pumpWidget(
              app(OverlayScenePicker(controller: owner), suite: suite),
            );
            await tester.pumpAndSettle();
            expect(owner.projection.value.preferredId, 'org:B');
          }
          expect(nativeViewportMenus.value, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

const targets = [
  OverlaySceneTarget('A', 'Alpha'),
  OverlaySceneTarget('B', 'Beta'),
];

class ScenePort implements OverlayScenePort {
  final events = StreamController<void>.broadcast();
  final pending = Completer<OverlaySceneState>();
  var state = const OverlaySceneState(
    revision: 7,
    mode: 'community',
    code: 'A',
    actualId: 'room',
    available: true,
    status: 'standby',
    targets: targets,
  );
  int writes = 0;
  bool closed = false;
  final arguments = <(int, String, String?)>[];
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<OverlaySceneState> read() async => state;
  @override
  Future<OverlaySceneState> select(int revision, String mode, String? code) {
    writes++;
    arguments.add((revision, mode, code));
    return pending.future;
  }

  @override
  Future<OverlaySceneState> focusCommunity(String code) async => state;
  @override
  Future<OverlaySceneState> focusFleet() => focusCommunity('');
  @override
  void close() {
    closed = true;
    unawaited(events.close());
  }
}
