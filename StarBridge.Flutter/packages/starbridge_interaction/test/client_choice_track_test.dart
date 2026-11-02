import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

class Tracked extends StatefulWidget {
  const Tracked(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Tracked> createState() => TrackedState();
}

class TrackedState extends State<Tracked> {
  var ids = ['a', 'b', 'c'], selected = 'a';
  var width = 95.0;
  var hostLayout = true;
  final calls = <(String, InteractionSource)>[];
  final repaint = GlobalKey();
  InteractionSource source = InteractionSource.programmatic;
  void change(VoidCallback fn) => setState(fn);
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: InteractionScope(
        data: InteractionData(suite: widget.suite, palette: palette),
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: repaint,
            child: SuiteSelectionTrack(
              style: TrackStyle.tabs,
              items: [for (final id in ids) TrackItem(id: id, label: id)],
              selected: ids.indexOf(selected),
              changeSource: source,
              onChanged: (i, input) => setState(() {
                calls.add((ids[i], input));
                selected = ids[i];
                source = input;
              }),
              layoutBuilder: !hostLayout
                  ? null
                  : (context, layout) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final id in ids)
                          layout.anchor(
                            id,
                            SuitePressable(
                              key: ValueKey(id),
                              kind: PressableKind.tab,
                              semanticLabel: id,
                              focusNode: layout.focusNode(id),
                              onActivate: (s) => layout.activate(id, s),
                              child: SizedBox(
                                width: id == 'b' ? width : 60,
                                height: 36,
                                child: Text(id),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<List<int>> pixels(WidgetTester t, GlobalKey key) async =>
    (await t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
        return bytes!.buffer.asUint8List().toList();
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite host and default layout can exchange without stale focus or geometry',
      (t) async {
        final key = GlobalKey<TrackedState>();
        await t.pumpWidget(Tracked(suite, key: key));
        await t.pumpAndSettle();
        final h = key.currentState!;
        h.change(() => h.hostLayout = false);
        await t.pumpAndSettle();
        await t.tap(find.text('b'));
        await t.pumpAndSettle();
        expect(h.selected, 'b');
        h.change(() => h.hostLayout = true);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('c')));
        await t.pumpAndSettle();
        expect(h.selected, 'c');
        h.change(() => h.hostLayout = false);
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, false);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite host track remeasures stable ids, keeps focus and hides absent selection',
      (t) async {
        final key = GlobalKey<TrackedState>();
        await t.pumpWidget(Tracked(suite, key: key));
        await t.pumpAndSettle();
        final h = key.currentState!;
        final node = t
            .widget<SuitePressable>(find.byKey(const ValueKey('a')))
            .focusNode!;
        node.requestFocus();
        await t.pumpAndSettle();
        h.change(() => h.ids = ['c', 'b', 'a']);
        await t.pumpAndSettle();
        final track = t.state<SuiteSelectionTrackState>(
          find.byType(SuiteSelectionTrack),
        );
        expect(
          t.widget<SuitePressable>(find.byKey(const ValueKey('a'))).focusNode,
          same(node),
        );
        expect(node.hasFocus, true);
        expect(track.indicatorRect, track.itemRect(2));
        h.change(() {
          h.selected = 'b';
          h.width = 151;
          h.source = InteractionSource.keyboard;
        });
        await t.pump();
        await t.pump();
        expect(track.indicatorRect, track.itemRect(1));
        expect(track.itemRect(1)!.width, 151);
        expect(
          track.isStretching || track.isSweeping || track.isRinging,
          false,
        );
        h.change(() => h.ids = ['a']);
        await t.pumpAndSettle();
        expect(track.indicatorRect, isNull);
        expect(h.calls, isEmpty);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, false);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite confirmed tab still acknowledges repeat pointer input',
      (t) async {
        final key = GlobalKey<TrackedState>();
        await t.pumpWidget(Tracked(suite, key: key));
        await t.pumpAndSettle();
        final h = key.currentState!;
        final idle = await pixels(t, h.repaint);
        await t.tap(find.byKey(const ValueKey('a')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(await pixels(t, h.repaint), isNot(idle));
        expect(h.calls, [('a', InteractionSource.pointer)]);
        await t.pumpAndSettle();
      },
    );
  }
}
