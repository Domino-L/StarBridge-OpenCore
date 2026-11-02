import 'dart:io';
import 'dart:ui' show PointerDeviceKind, SemanticsAction, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch2b_test.dart' show BookmarkPort;
import '../../features/friends/social_layout_test.dart' show loadFonts;

const target = Key('hint-target');
const hint = 'Bookmark ship';

Future<void> captureHint(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3C'] != '1') return;
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final directory = Directory('build/reviews/interaction-batch3c');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite icon hint has one spoken label while visible', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      try {
        final calls = <InteractionSource>[];
        await t.pumpWidget(
          app(
            StarBridgeIconAction(
              controlKey: target,
              label: hint,
              onActivate: calls.add,
              icon: const Icon(Icons.bookmark_border),
            ),
            suite: suite,
          ),
        );
        await t.pumpAndSettle();
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: t.getCenter(find.byKey(target)));
        await t.pump(const Duration(milliseconds: 500));
        await t.pumpAndSettle();
        expect(find.text(hint), findsOneWidget);
        final nodes = exposedNodes(t);
        expect(
          nodes.where((n) => n.getSemanticsData().label == hint),
          hasLength(1),
        );
        expect(
          nodes.where((n) => n.getSemanticsData().tooltip == hint),
          isEmpty,
        );
        final node = nodes.singleWhere(
          (n) => n.getSemanticsData().label == hint,
        );
        t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await t.pump();
        expect(calls, [InteractionSource.keyboard]);
        await mouse.removePointer();
        await t.pumpAndSettle();
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('$suite Escape dismisses focused hint without moving focus', (
      t,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await t.pumpWidget(
        app(
          StarBridgeTooltip(
            message: 'Keyboard hint',
            child: Focus(
              focusNode: focus,
              child: const SizedBox(
                key: target,
                width: 50,
                height: 50,
                child: Text('Target'),
              ),
            ),
          ),
          suite: suite,
        ),
      );
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      focus.requestFocus();
      await t.pump();
      await t.pump();
      expect(find.text('Keyboard hint'), findsOneWidget);
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('Keyboard hint'), findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('$suite touch long press shows hint then expires', (t) async {
      var calls = 0;
      await t.pumpWidget(
        app(
          StarBridgeTooltip(
            message: 'Touch hint',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              key: target,
              onTap: () => calls++,
              child: const SizedBox(width: 50, height: 50),
            ),
          ),
          suite: suite,
        ),
      );
      await t.pumpAndSettle();
      final touch = await t.startGesture(t.getCenter(find.byKey(target)));
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Touch hint'), findsOneWidget);
      await touch.up();
      await t.pump(const Duration(milliseconds: 1700));
      await t.pumpAndSettle();
      expect(find.text('Touch hint'), findsNothing);
      expect(calls, 0);
    });

    for (final exiting in [false, true]) {
      testWidgets('$suite live local reduce during hint exit=$exiting', (
        t,
      ) async {
        var reduce = false;
        late StateSetter update;
        await t.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, set) {
                update = set;
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduce),
                  child: const StarBridgeTooltip(
                    message: 'Live hint',
                    waitDuration: Duration.zero,
                    child: ColoredBox(
                      color: Colors.blue,
                      child: SizedBox(key: target, width: 50, height: 50),
                    ),
                  ),
                );
              },
            ),
            suite: suite,
          ),
        );
        await t.pumpAndSettle();
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: t.getCenter(find.byKey(target)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 25));
        expect(find.text('Live hint'), findsOneWidget);
        if (exiting) {
          await t.pumpAndSettle();
          await mouse.removePointer();
          await t.pump();
          await t.pump(const Duration(milliseconds: 20));
          expect(find.text('Live hint'), findsOneWidget);
        }
        update(() => reduce = true);
        await t.pump();
        await t.pump();
        if (exiting) {
          expect(find.text('Live hint'), findsNothing);
        } else {
          expect(
            t
                .widget<Opacity>(
                  find
                      .ancestor(
                        of: find.text('Live hint'),
                        matching: find.byType(Opacity),
                      )
                      .first,
                )
                .opacity,
            1,
          );
          await mouse.removePointer();
          await t.pump();
          expect(find.text('Live hint'), findsNothing);
        }
        expect(t.binding.hasScheduledFrame, isFalse);
      });
    }

    for (final empty in [false, true]) {
      testWidgets('$suite live suppression empty=$empty and label retarget', (
        t,
      ) async {
        var visible = true;
        var message = 'Old hint';
        late StateSetter update;
        await t.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, set) {
                update = set;
                return TooltipVisibility(
                  visible: visible,
                  child: StarBridgeTooltip(
                    message: message,
                    waitDuration: Duration.zero,
                    child: const ColoredBox(
                      color: Colors.blue,
                      child: SizedBox(key: target, width: 50, height: 50),
                    ),
                  ),
                );
              },
            ),
            suite: suite,
          ),
        );
        await t.pumpAndSettle();
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: t.getCenter(find.byKey(target)));
        await t.pumpAndSettle();
        expect(find.text('Old hint'), findsOneWidget);
        update(() => message = 'New hint');
        await t.pump();
        expect(find.text('Old hint'), findsNothing);
        expect(find.text('New hint'), findsOneWidget);
        update(() {
          if (empty) {
            message = '';
          } else {
            visible = false;
          }
        });
        await t.pump();
        await t.pump();
        expect(find.text('New hint'), findsNothing);
        final touch = await t.startGesture(t.getCenter(find.byKey(target)));
        await t.pump(const Duration(milliseconds: 700));
        expect(find.text('New hint'), findsNothing);
        await touch.up();
        await mouse.removePointer();
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('$suite style change preserves focused child and overlay', (
      t,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final childKey = GlobalKey();
      final next = InteractionSuite.values[(suite.index + 1) % 4];
      Widget view(InteractionSuite style) => app(
        StarBridgeTooltip(
          message: 'Stable hint',
          child: Focus(
            key: childKey,
            focusNode: focus,
            child: const Text('Target'),
          ),
        ),
        suite: style,
      );
      await t.pumpWidget(view(suite));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      focus.requestFocus();
      await t.pump();
      await t.pump();
      final oldElement = childKey.currentContext;
      expect(find.text('Stable hint'), findsOneWidget);
      await t.pumpWidget(view(next));
      await t.pump();
      expect(childKey.currentContext, same(oldElement));
      expect(focus.hasFocus, isTrue);
      expect(find.text('Stable hint'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('Stable hint'), findsNothing);
    });

    testWidgets('$suite pending hover cancels on press or disposal', (t) async {
      var calls = 0;
      Widget view() => app(
        StarBridgeTooltip(
          message: 'Pending hint',
          waitDuration: const Duration(days: 1),
          child: GestureDetector(
            key: target,
            behavior: HitTestBehavior.opaque,
            onTap: () => calls++,
            child: const SizedBox(width: 50, height: 50),
          ),
        ),
        suite: suite,
      );
      await t.pumpWidget(view());
      await t.pumpAndSettle();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      // Browsing may show at once; cancellation must work on either path.
      await mouse.addPointer(location: t.getCenter(find.byKey(target)));
      await t.pump(const Duration(milliseconds: 10));
      await t.tap(find.byKey(target));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Pending hint'), findsNothing);
      await mouse.removePointer();
      await mouse.addPointer(location: t.getCenter(find.byKey(target)));
      await t.pumpWidget(const SizedBox());
      await mouse.removePointer();
      await t.pump(const Duration(days: 2));
      expect(t.takeException(), isNull);
    });

    testWidgets('$suite focused hint follows scrolling anchor without ticker', (
      t,
    ) async {
      final scroll = ScrollController();
      final focus = FocusNode();
      addTearDown(scroll.dispose);
      addTearDown(focus.dispose);
      await t.pumpWidget(
        app(
          SizedBox(
            width: 300,
            height: 400,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 180),
                  StarBridgeTooltip(
                    message: 'Scroll hint',
                    child: Focus(
                      focusNode: focus,
                      child: const SizedBox(
                        key: target,
                        width: 50,
                        height: 50,
                        child: Text('Target'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 700),
                ],
              ),
            ),
          ),
          suite: suite,
        ),
      );
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      focus.requestFocus();
      await t.pump();
      await t.pump();
      final initial = t.getRect(find.text('Scroll hint'));
      scroll.jumpTo(100);
      await t.pump();
      await t.pump();
      final moved = t.getRect(find.text('Scroll hint'));
      expect(moved.top, closeTo(initial.top - 100, .01));
      expect(focus.hasFocus, isTrue);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    for (final grid in [false, true]) {
      testWidgets('$suite real hangar hint read-only grid=$grid', (t) async {
        final port = BookmarkPort();
        final boundary = GlobalKey();
        if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3C'] == '1') {
          await loadFonts();
        }
        final template = app(
          LocalHangarPage(port: port, onRead: () {}),
          suite: suite,
        ) as MaterialApp;
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: template.theme,
              themeAnimationDuration: Duration.zero,
              locale: template.locale,
              supportedLocales: template.supportedLocales,
              localizationsDelegates: template.localizationsDelegates,
              home: template.home,
              debugShowCheckedModeBanner: false,
            ),
          ),
        );
        await t.pumpAndSettle();
        if (!grid) {
          await t.tap(find.byKey(const Key('hangar-list')));
          await t.pumpAndSettle();
        }
        final button = find.byKey(const ValueKey('hangar-favorite-one'));
        await t.ensureVisible(button);
        await t.pump();
        final tooltip = find.ancestor(
          of: button,
          matching: find.byType(StarBridgeTooltip),
        );
        expect(tooltip, findsOneWidget);
        final label = t.widget<StarBridgeTooltip>(tooltip).message;
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: t.getCenter(button));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        await t.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(port.writes, 0);
        expect(port.reads, 1);
        await captureHint(
          t,
          boundary,
          '${suite.name}-${grid ? 'grid' : 'list'}',
        );
        await mouse.removePointer();
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        expect(port.writes, 0);
      });
    }

    for (final rtl in [false, true]) {
      for (final corner in [
        Alignment.topLeft,
        Alignment.topRight,
        Alignment.bottomLeft,
        Alignment.bottomRight,
      ]) {
        testWidgets('$suite edge hint $corner rtl=$rtl scaled', (t) async {
          await t.binding.setSurfaceSize(const Size(360, 220));
          addTearDown(() => t.binding.setSurfaceSize(null));
          const text =
              'A longer explanation with several lines of useful details';
          await t.pumpWidget(
            app(
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: SizedBox.expand(
                    child: Align(
                      alignment: corner,
                      child: const StarBridgeTooltip(
                        message: text,
                        waitDuration: Duration.zero,
                        child: ColoredBox(
                          color: Colors.blue,
                          child: SizedBox(key: target, width: 24, height: 24),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              suite: suite,
            ),
          );
          await t.pumpAndSettle();
          final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: t.getCenter(find.byKey(target)));
          await t.pumpAndSettle();
          final rect = t.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(8));
          expect(rect.top, greaterThanOrEqualTo(8));
          expect(rect.right, lessThanOrEqualTo(352));
          expect(rect.bottom, lessThanOrEqualTo(212));
          expect(t.takeException(), isNull);
          final hits = t.hitTestOnBinding(rect.center);
          expect(
            hits.path.any(
              (entry) =>
                  entry.target.runtimeType.toString() == 'RenderParagraph',
            ),
            isFalse,
          );
          await mouse.removePointer();
          await t.pumpAndSettle();
        });
      }
    }
  }
}
