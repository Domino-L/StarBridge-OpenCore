import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

class DirectionHarness extends StatefulWidget {
  const DirectionHarness(this.suite, this.style, this.host, {super.key});
  final InteractionSuite suite;
  final TrackStyle style;
  final bool host;
  @override
  State<DirectionHarness> createState() => DirectionState();
}

class DirectionState extends State<DirectionHarness> {
  var selected = 0;
  InteractionSource source = InteractionSource.programmatic;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: InteractionScope(
          data: InteractionData(suite: widget.suite, palette: palette),
          child: SuiteSelectionTrack(
            style: widget.style,
            items: const [
              TrackItem(id: 'a', label: 'a'),
              TrackItem(id: 'b', label: 'b', enabled: false),
              TrackItem(id: 'c', label: 'c'),
              TrackItem(id: 'd', label: 'd'),
            ],
            selected: selected,
            changeSource: source,
            onChanged: (i, input) => setState(() {
              selected = i;
              source = input;
            }),
            layoutBuilder: !widget.host
                ? null
                : (context, layout) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final id in ['a', 'b', 'c', 'd'])
                        layout.anchor(
                          id,
                          SuitePressable(
                            key: ValueKey(id),
                            kind: PressableKind.tab,
                            focusNode: layout.focusNode(id),
                            onActivate: id == 'b'
                                ? null
                                : (s) => layout.activate(id, s),
                            child: SizedBox(
                              width: 64,
                              height: 44,
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
  );
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final host in [false, true]) {
      testWidgets(
        '$suite RTL horizontal keyboard visual direction host=$host',
        (t) async {
          final key = GlobalKey<DirectionState>();
          await t.pumpWidget(
            DirectionHarness(suite, TrackStyle.tabs, host, key: key),
          );
          await t.pumpAndSettle();
          await t.tap(find.text('a'));
          await t.pumpAndSettle();
          t
              .widget<SuitePressable>(find.widgetWithText(SuitePressable, 'a'))
              .focusNode!
              .requestFocus();
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await t.pump();
          await t.pump();
          expect(key.currentState!.selected, 2);
          expect(key.currentState!.source, InteractionSource.keyboard);
          final state = t.state<SuiteSelectionTrackState>(
            find.byType(SuiteSelectionTrack),
          );
          expect(state.indicatorRect, state.itemRect(2));
          expect(
            state.isStretching || state.isSweeping || state.isRinging,
            false,
          );
          await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await t.pump();
          await t.pump();
          expect(key.currentState!.selected, 0);
          await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await t.pump();
          await t.pump();
          expect(key.currentState!.selected, 3);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets('$suite RTL vertical arrows keep their original order', (
      t,
    ) async {
      final key = GlobalKey<DirectionState>();
      await t.pumpWidget(
        DirectionHarness(suite, TrackStyle.navigation, false, key: key),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('a'));
      await t.pumpAndSettle();
      t
          .widget<SuitePressable>(find.widgetWithText(SuitePressable, 'a'))
          .focusNode!
          .requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await t.pump();
      expect(key.currentState!.selected, 2);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      await t.pump();
      expect(key.currentState!.selected, 0);
      expect(t.takeException(), isNull);
    });
  }
}
