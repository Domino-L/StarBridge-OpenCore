// Batch 5 (O02): link (04), server-confirmed switch (06), clickable
// popover (14), image rotation (20), overlay layout editor (21), chat
// attachments (31).
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

const _animated = [InteractionSuite.rail, InteractionSuite.scan, InteractionSuite.glow];

Widget _host(InteractionSuite suite, Widget child, {bool reduce = false}) => InteractionScope(
  data: InteractionData(suite: suite, palette: palette, reduceMotion: reduce),
  child: MaterialApp(home: Scaffold(body: child)),
);

/// Host whose reduced-motion flag can flip mid-test.
Widget _live(InteractionSuite suite, ValueNotifier<bool> reduce, Widget child) => ValueListenableBuilder(
  valueListenable: reduce,
  builder: (context, r, _) => _host(suite, child, reduce: r),
);

void main() {
  group('04 link', () {
    for (final suite in _animated) {
      testWidgets('${suite.name}: hover cue plays; Enter opens as keyboard; never a ripple', (t) async {
        final opened = <InteractionSource>[];
        await t.pumpWidget(_host(suite, Center(child: SuiteLink(label: '查看规则', onTap: opened.add))));
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: t.getCenter(find.text('查看规则')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        expect(t.hasRunningAnimations, isTrue);
        await t.pumpAndSettle();
        await t.tap(find.text('查看规则'));
        await t.pump();
        expect(opened, [InteractionSource.pointer]);
        expect(find.byType(InkWell), findsNothing);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(opened.last, InteractionSource.keyboard);
        await mouse.removePointer();
      });
    }

    testWidgets('standard and reduced motion: the hover cue is instant', (t) async {
      for (final (suite, reduce) in [(InteractionSuite.standard, false), (InteractionSuite.glow, true)]) {
        await t.pumpWidget(_host(suite, reduce: reduce, Center(child: SuiteLink(label: '官网', external: true, onTap: (_) {}))));
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: t.getCenter(find.text('官网')));
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        await mouse.removePointer();
      }
    });

    testWidgets('a link is a link to screen readers; disabled has no action and no focus', (t) async {
      final handle = t.ensureSemantics();
      var taps = 0;
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          Column(
            children: [
              SuiteLink(label: '查看规则', onTap: (_) => taps++),
              const SuiteLink(label: '已失效', onTap: null),
            ],
          ),
        ),
      );
      final on = t.getSemantics(find.byType(SuiteLink).first).getSemanticsData();
      expect(on.flagsCollection.isLink, isTrue);
      expect(on.hasAction(SemanticsAction.tap), isTrue);
      t.semantics.tap(find.semantics.byLabel('查看规则'));
      expect(taps, 1);
      final off = t.getSemantics(find.byType(SuiteLink).last).getSemanticsData();
      expect(off.hasAction(SemanticsAction.tap), isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SuiteLink>()?.label, isNot('已失效'));
      handle.dispose();
    });
  });

  group('06 switch waiting for the server', () {
    Widget pendingSwitch(InteractionSuite suite, {bool reduce = false, required void Function(StateSetter, bool) onChanged, required bool value, bool? pending, bool error = false}) =>
        _host(
          suite,
          reduce: reduce,
          Center(
            child: StatefulBuilder(
              builder: (context, set) => SuiteSwitch(
                value: value,
                pendingValue: pending,
                error: error,
                semanticLabel: '云同步',
                onChanged: (v) => onChanged(set, v),
              ),
            ),
          ),
        );

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: request → waits (no more input) → confirmed settles quietly', (t) async {
        var value = false;
        bool? pending;
        var calls = 0;
        late StateSetter outer;
        Widget build() => pendingSwitch(suite, value: value, pending: pending, onChanged: (_, v) {
          calls++;
          outer(() => pending = v);
        });
        await t.pumpWidget(StatefulBuilder(builder: (context, s) {
          outer = s;
          return build();
        }));
        await t.tap(find.byType(SuiteSwitch));
        await t.pump();
        expect(calls, 1);
        expect(pending, isTrue);
        // Past the press feedback tail (scan beam, glow ring).
        await t.pump(const Duration(milliseconds: 900));
        // Waiting: further taps are ignored.
        await t.tap(find.byType(SuiteSwitch));
        await t.pump();
        expect(calls, 1);
        expect(find.bySemanticsLabel(RegExp('正在确认')), findsOneWidget);
        // Confirmed.
        outer(() {
          value = true;
          pending = null;
        });
        await t.pump();
        await t.pump(const Duration(milliseconds: 16));
        expect(t.hasRunningAnimations, isFalse, reason: 'nothing more plays on confirmation');
      });
    }

    for (final suite in _animated) {
      testWidgets('${suite.name}: refused → the knob returns without decoration; error edge stays static', (t) async {
        var value = false;
        bool? pending;
        var error = false;
        late StateSetter outer;
        await t.pumpWidget(StatefulBuilder(builder: (context, s) {
          outer = s;
          return pendingSwitch(suite, value: value, pending: pending, error: error, onChanged: (set, v) => s(() => pending = v));
        }));
        await t.tap(find.byType(SuiteSwitch));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        outer(() {
          pending = null;
          error = true;
        });
        await t.pump();
        await t.pumpAndSettle();
        expect(value, isFalse);
        expect(t.hasRunningAnimations, isFalse);
        expect(find.bySemanticsLabel(RegExp('未能更改')), findsOneWidget);
      });
    }

    testWidgets('reduced motion: the waiting mark is static (no loop)', (t) async {
      await t.pumpWidget(pendingSwitch(InteractionSuite.glow, reduce: true, value: false, pending: true, onChanged: (_, _) {}));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion turned on while waiting stops the loop at once', (t) async {
      final reduce = ValueNotifier(false);
      addTearDown(reduce.dispose);
      await t.pumpWidget(_live(InteractionSuite.rail, reduce, const Center(child: SuiteSwitch(value: false, pendingValue: true, onChanged: null))));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.hasRunningAnimations, isTrue);
      reduce.value = true;
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('a keyboard request keeps focus on the switch while waiting', (t) async {
      bool? pending;
      await t.pumpWidget(StatefulBuilder(builder: (context, s) => pendingSwitch(InteractionSuite.scan, value: false, pending: pending, onChanged: (set, v) => s(() => pending = v))));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final focused = FocusManager.instance.primaryFocus;
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(pending, isTrue);
      expect(FocusManager.instance.primaryFocus, same(focused));
    });
  });

  group('14 popover', () {
    Widget pop(InteractionSuite suite, {Alignment where = Alignment.topCenter, bool reduce = false, List<String>? log}) => _host(
      suite,
      reduce: reduce,
      Align(
        alignment: where,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SuitePopover(
            semanticLabel: '成员资料',
            anchorBuilder: (context, open) => const Text('千禧'),
            contentBuilder: (context, close) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => log?.add('msg'), child: const Text('发消息')),
                TextButton(
                  onPressed: () {
                    log?.add('invite');
                    close();
                  },
                  child: const Text('邀请'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: click opens with focus inside; Tab stays inside; Esc closes and returns focus', (t) async {
        await t.pumpWidget(pop(suite));
        await t.tap(find.text('千禧'));
        await t.pumpAndSettle();
        expect(find.text('发消息'), findsOneWidget);
        bool inside() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>() != null;
        expect(inside(), isTrue, reason: '${FocusManager.instance.primaryFocus}');
        for (var i = 0; i < 3; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
          expect(inside(), isTrue, reason: 'Tab stays in the panel: ${FocusManager.instance.primaryFocus}');
        }
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.text('发消息'), findsNothing, reason: 'Esc closes at once');
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'popover-anchor');
      });
    }

    testWidgets('hovering never opens it; outside tap closes it; an inner action can close it', (t) async {
      final log = <String>[];
      await t.pumpWidget(pop(InteractionSuite.glow, log: log));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(find.text('千禧')));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('发消息'), findsNothing);
      await mouse.removePointer();
      await t.tap(find.text('千禧'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(5, 590));
      await t.pumpAndSettle();
      expect(find.text('发消息'), findsNothing);
      await t.tap(find.text('千禧'));
      await t.pumpAndSettle();
      await t.tap(find.text('邀请'));
      await t.pumpAndSettle();
      expect(log, ['invite']);
      expect(find.text('邀请'), findsNothing);
    });

    for (final suite in _animated) {
      testWidgets('${suite.name}: keyboard opening is complete on the first frame', (t) async {
        await t.pumpWidget(pop(suite));
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(find.text('发消息'), findsOneWidget);
        final state = t.state<SuitePopoverState>(find.byType(SuitePopover));
        expect(state.isOpen, isTrue);
        final first = t.getRect(find.text('发消息'));
        await t.pumpAndSettle();
        expect(t.getRect(find.text('发消息')), first, reason: 'no entrance movement');
      });

      testWidgets('${suite.name}: reduced motion mid-entrance settles', (t) async {
        final reduce = ValueNotifier(false);
        addTearDown(reduce.dispose);
        await t.pumpWidget(ValueListenableBuilder(valueListenable: reduce, builder: (context, r, _) => pop(suite, reduce: r)));
        await t.tap(find.text('千禧'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(t.hasRunningAnimations, isTrue);
        reduce.value = true;
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('near the bottom it opens above; it stays inside the window', (t) async {
      t.view.physicalSize = const Size(800, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(pop(InteractionSuite.rail, where: Alignment.bottomRight));
      await t.tap(find.text('千禧'));
      await t.pumpAndSettle();
      final anchor = t.getRect(find.text('千禧'));
      final panel = t.getRect(find.text('发消息'));
      expect(panel.bottom, lessThan(anchor.top));
      final container = t.getRect(find.ancestor(of: find.text('发消息'), matching: find.byType(Container)).last);
      expect(container.right, lessThanOrEqualTo(792));
      expect(container.left, greaterThanOrEqualTo(8));
    });
  });

  group('20 image rotation', () {
    Widget viewer(InteractionSuite suite, GlobalKey<SuiteImageViewerState> key, {List<int>? log}) => _host(
      suite,
      SizedBox(width: 400, child: SuiteImageViewer(key: key, image: const ColoredBox(color: Colors.teal), onRotationChanged: log?.add)),
    );

    for (final suite in _animated) {
      testWidgets('${suite.name}: a click turns a quarter turn with an eased motion; quick presses keep turning clockwise', (t) async {
        final key = GlobalKey<SuiteImageViewerState>();
        final log = <int>[];
        await t.pumpWidget(viewer(suite, key, log: log));
        await t.tap(find.byIcon(Icons.rotate_right));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        expect(t.hasRunningAnimations, isTrue);
        expect(key.currentState!.quarterTurns, 1, reason: 'the real orientation changes at once');
        await t.tap(find.byIcon(Icons.rotate_right));
        await t.pumpAndSettle();
        expect(key.currentState!.quarterTurns, 2);
        expect(log, [1, 2]);
      });

      testWidgets('${suite.name}: keyboard rotation lands at once; reduced motion mid-turn settles', (t) async {
        final key = GlobalKey<SuiteImageViewerState>();
        await t.pumpWidget(viewer(suite, key));
        key.currentState!.rotate(source: InteractionSource.keyboard);
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        expect(key.currentState!.quarterTurns, 1);
      });
    }

    testWidgets('the turned image always fits inside the frame', (t) async {
      final key = GlobalKey<SuiteImageViewerState>();
      await t.pumpWidget(viewer(InteractionSuite.rail, key));
      key.currentState!.rotate(source: InteractionSource.keyboard);
      await t.pump();
      final frame = t.getRect(find.byType(InteractiveViewer));
      final image = t.getRect(find.byType(ColoredBox).last);
      // Rotated 90°: the box's rendered bounds stay inside the frame.
      expect(image.width, lessThanOrEqualTo(frame.width + 0.5));
      expect(image.height, lessThanOrEqualTo(frame.height + 0.5));
    });
  });

  group('21 layout editor', () {
    const boxes = [
      LayoutBox(id: 'players', label: '玩家列表', rect: Rect.fromLTWH(100, 100, 200, 120)),
      LayoutBox(id: 'voice', label: '语音指示', rect: Rect.fromLTWH(600, 400, 160, 60)),
    ];

    Future<({List<List<LayoutBox>> commits, List<LayoutEditKind> kinds})> editor(WidgetTester t, InteractionSuite suite, {bool reduce = false}) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final commits = <List<LayoutBox>>[];
      final kinds = <LayoutEditKind>[];
      var current = boxes;
      await t.pumpWidget(
        _host(
          suite,
          reduce: reduce,
          StatefulBuilder(
            builder: (context, s) => SuiteLayoutEditor(
              boxes: current,
              onChanged: (b, k) => s(() {
                current = b;
                commits.add(b);
                kinds.add(k);
              }),
            ),
          ),
        ),
      );
      return (commits: commits, kinds: kinds);
    }

    Rect boxRect(WidgetTester t, String label) =>
        t.getRect(find.ancestor(of: find.text(label), matching: find.byType(CustomPaint)).first);

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: dragging follows the pointer exactly, one commit per drag', (t) async {
        final r = await editor(t, suite);
        final scale = t.getSize(find.byType(SuiteLayoutEditor)).width / 1280;
        final before = boxRect(t, '玩家列表');
        final g = await t.startGesture(before.center);
        for (var i = 1; i <= 5; i++) {
          await g.moveBy(const Offset(20, 10));
          await t.pump();
          final now = boxRect(t, '玩家列表');
          expect(now.left - before.left, closeTo(20.0 * i, 0.01), reason: 'no lag, no easing');
        }
        await g.up();
        await t.pump();
        expect(r.commits, hasLength(1));
        expect(r.kinds.single, LayoutEditKind.move);
        expect(r.commits.single.first.rect.left, closeTo(100 + 100 / scale, 0.5));
      });
    }

    for (final suite in _animated) {
      testWidgets('${suite.name}: near a line it snaps and the guide appears with the suite cue', (t) async {
        final r = await editor(t, suite);
        final scale = t.getSize(find.byType(SuiteLayoutEditor)).width / 1280;
        final before = boxRect(t, '玩家列表');
        // Move the left edge to x = 4 (virtual): within 6 px of the window edge.
        final g = await t.startGesture(before.center);
        await g.moveBy(Offset(-96 * scale, 0));
        await t.pump();
        expect(t.hasRunningAnimations, isTrue, reason: 'guide cue');
        await g.up();
        await t.pump();
        expect(r.commits.single.first.rect.left, 0);
      });
    }

    testWidgets('holding Alt places freely; reduced motion shows static guides', (t) async {
      final r = await editor(t, InteractionSuite.rail, reduce: true);
      final scale = t.getSize(find.byType(SuiteLayoutEditor)).width / 1280;
      final before = boxRect(t, '玩家列表');
      var g = await t.startGesture(before.center);
      await g.moveBy(Offset(-96 * scale, 0));
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      await g.up();
      await t.pump();
      expect(r.commits.last.first.rect.left, 0);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final at = boxRect(t, '玩家列表');
      g = await t.startGesture(at.center);
      await g.moveBy(Offset(40 * scale, 0));
      await g.moveBy(Offset(-38 * scale, 0));
      await t.pump();
      await g.up();
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(r.commits.last.first.rect.left, closeTo(2, 0.5));
    });

    testWidgets('resize handles change size and respect the minimum', (t) async {
      final r = await editor(t, InteractionSuite.scan);
      await t.tap(find.text('玩家列表'));
      await t.pump();
      final box = boxRect(t, '玩家列表');
      final g = await t.startGesture(box.centerRight);
      await g.moveBy(const Offset(-500, 0));
      await t.pump();
      await g.up();
      await t.pump();
      expect(r.kinds.last, LayoutEditKind.resize);
      expect(r.commits.last.first.rect.width, 60, reason: 'minimum width');
      expect(r.commits.last.first.rect.left, 100, reason: 'the fixed edge stays');
    });

    testWidgets('keyboard: arrows nudge 1, Shift 10, Ctrl resizes; each press commits as a nudge', (t) async {
      final r = await editor(t, InteractionSuite.glow);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(r.kinds, everyElement(LayoutEditKind.nudge));
      expect(r.commits.last.first.rect, const Rect.fromLTWH(101, 110, 201, 120));
      expect(t.hasRunningAnimations, isFalse);
      expect(find.textContaining('x 101 · y 110'), findsOneWidget, reason: 'real readout');
    });
  });

  group('31 chat attachments', () {
    const a = SuiteAttachment(id: 'a', name: '航线图.png', sizeLabel: '1.2 MB', isImage: true, phase: AttachmentPhase.uploading, progress: 0.3);
    const b = SuiteAttachment(id: 'b', name: '货单.pdf', sizeLabel: '240 KB', phase: AttachmentPhase.failed, progress: 0.6);

    for (final suite in _animated) {
      testWidgets('${suite.name}: chips already there do not replay; a new one enters; done fades the line', (t) async {
        var list = [a.copyWith(phase: AttachmentPhase.done, progress: 1)];
        late StateSetter set;
        await t.pumpWidget(_host(suite, StatefulBuilder(builder: (context, s) {
          set = s;
          return SuiteAttachmentTray(attachments: list, onRemove: (_) {}, onRetry: (_) {});
        })));
        await t.pump();
        expect(t.hasRunningAnimations, isFalse, reason: 'no replay on mount');
        set(() => list = [...list, const SuiteAttachment(id: 'c', name: '截图.jpg', sizeLabel: '800 KB', isImage: true, phase: AttachmentPhase.uploading, progress: 0.1)]);
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(t.hasRunningAnimations, isTrue, reason: 'new chip enters');
        await t.pumpAndSettle();
        set(() => list = [list[0], list[1].copyWith(phase: AttachmentPhase.done, progress: 1)]);
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(t.hasRunningAnimations, isTrue, reason: 'progress completes and fades');
        await t.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp('截图.jpg.*已上传')), findsOneWidget);
      });
    }

    testWidgets('failed: static, retry and remove report; Delete removes; focus moves on', (t) async {
      final retried = <String>[], removed = <String>[];
      var list = [b, a];
      await t.pumpWidget(_host(InteractionSuite.scan, StatefulBuilder(builder: (context, s) => SuiteAttachmentTray(
        attachments: list,
        onRemove: (id) => s(() {
          removed.add(id);
          list = list.where((x) => x.id != id).toList();
        }),
        onRetry: retried.add,
      ))));
      await t.pump();
      expect(find.text('上传失败'), findsOneWidget);
      expect(t.hasRunningAnimations, isFalse);
      await t.tap(find.bySemanticsLabel('重试上传货单.pdf'));
      await t.pump();
      expect(retried, ['b']);
      // Focus the failed chip's remove button and press Delete.
      Focus.of(t.element(find.byIcon(Icons.close).first)).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pump();
      await t.pump();
      expect(removed, ['b']);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'attachment-a');
    });

    testWidgets('reduced motion: new chips appear in place', (t) async {
      var list = <SuiteAttachment>[];
      late StateSetter set;
      await t.pumpWidget(_host(InteractionSuite.glow, reduce: true, StatefulBuilder(builder: (context, s) {
        set = s;
        return SuiteAttachmentTray(attachments: list, onRemove: (_) {}, onRetry: (_) {});
      })));
      set(() => list = [a]);
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      expect(t.hasRunningAnimations, isFalse, reason: 'at most a one-frame resize');
    });

    testWidgets('a sent message shows its attachments as static rows', (t) async {
      await t.pumpWidget(_host(InteractionSuite.rail, SuiteMessageBubble(text: '', mine: true, attachments: [a.copyWith(phase: AttachmentPhase.done)])));
      expect(find.text('航线图.png'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('附件 航线图.png')), findsOneWidget);
    });
  });

  testWidgets('image viewer and layout editor work inside IntrinsicHeight rows', (t) async {
    await t.pumpWidget(
      _host(
        InteractionSuite.rail,
        SingleChildScrollView(
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: SuiteImageViewer(image: ColoredBox(color: Colors.teal), height: 120)),
                Expanded(
                  child: SuiteLayoutEditor(
                    canvasSize: const Size(640, 360),
                    boxes: const [LayoutBox(id: 'a', label: 'A', rect: Rect.fromLTWH(10, 10, 100, 60))],
                    onChanged: (_, _) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    final editor = t.getSize(find.byType(SuiteLayoutEditor));
    expect(editor.width / editor.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('a touch drag on a box inside a scroll view moves the box, not the page', (t) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final commits = <List<LayoutBox>>[];
    await t.pumpWidget(
      _host(
        InteractionSuite.rail,
        ListView(
          controller: scroll,
          children: [
            const SizedBox(height: 50),
            SizedBox(
              width: 640,
              child: SuiteLayoutEditor(
                canvasSize: const Size(640, 360),
                boxes: const [LayoutBox(id: 'a', label: 'A', rect: Rect.fromLTWH(200, 200, 100, 60))],
                onChanged: (b, _) => commits.add(b),
              ),
            ),
            const SizedBox(height: 900),
          ],
        ),
      ),
    );
    final g = await t.startGesture(t.getCenter(find.text('A')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -12));
      await t.pump();
    }
    await g.up();
    await t.pump();
    expect(scroll.offset, 0);
    expect(commits, hasLength(1));
    expect(commits.single.single.rect.top, lessThan(200));
  });
}
