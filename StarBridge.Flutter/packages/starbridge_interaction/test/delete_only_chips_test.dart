import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Widget host(InteractionSuite suite, Widget child, {bool reduce = false}) =>
    InteractionScope(
      data: InteractionData(
        suite: suite,
        palette: palette,
        reduceMotion: reduce,
      ),
      child: MaterialApp(home: Scaffold(body: child)),
    );
const green = Color(0xff77cc99);
SuiteChipData chip(String id) => SuiteChipData(
  id: id,
  label: id.toUpperCase(),
  removable: true,
  side: const BorderSide(color: green),
  backgroundColor: green.withValues(alpha: .14),
  removeLabel: 'Remove $id',
);
Finder remove(String id) => find.byKey(ValueKey<Object>(('chip-remove', id)));
void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('delete-only face and exact source $suite $source', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final nodes = {'a': FocusNode(), 'b': FocusNode()};
        final fallback = FocusNode();
        try {
          var ids = ['a', 'b'];
          final calls = <(String, InteractionSource)>[];
          InteractionSource? change;
          await t.pumpWidget(
            host(
              suite,
              StatefulBuilder(
                builder: (context, set) => Column(
                  children: [
                    SuiteChipGroup(
                      chips: [for (final id in ids) chip(id)],
                      onToggle: null,
                      focusNodeForId: (id) => nodes[id]!,
                      fallbackFocus: fallback,
                      changeSource: change,
                      onRemoveWithSource: (id, s) => set(() {
                        calls.add((id, s));
                        change = s;
                        ids.remove(id);
                      }),
                    ),
                    TextField(focusNode: fallback),
                  ],
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.text('A'));
          await t.pump();
          expect(calls, isEmpty);
          final target = remove('a');
          if (source == 'pointer') {
            await t.tap(target);
          } else if (source == 'keyboard') {
            nodes['a']!.requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.delete);
          } else {
            final n = t.getSemantics(target);
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              n.id,
              SemanticsAction.tap,
            );
          }
          await t.pump();
          expect(ids, ['b']);
          expect(calls, [
            (
              "a",
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ),
          ]);
          if (source != 'pointer') {
            expect(find.byKey(const ValueKey('a')), findsNothing);
          }
          if (source == 'keyboard') {
            expect(nodes['b']!.hasFocus, true);
          }
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('a')), findsNothing);
          await t.pumpWidget(const SizedBox());
          nodes['a']!.addListener(
            () {},
          ); // Group must not dispose supplied focus.
        } finally {
          semantics.dispose();
          for (final n in nodes.values) {
            n.dispose();
          }
          fallback.dispose();
        }
      });
    }
    testWidgets('delete restore retains one face and classification $suite', (
      t,
    ) async {
      var ids = ['a', 'b'];
      late StateSetter change;
      await t.pumpWidget(
        host(
          suite,
          StatefulBuilder(
            builder: (context, set) {
              change = set;
              return SuiteChipGroup(
                chips: [for (final id in ids) chip(id)],
                onToggle: null,
                onRemoveWithSource: (id, _) => set(() => ids.remove(id)),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(remove('a'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      final outer = find
          .descendant(
            of: find.byKey(const ValueKey('a')),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final style = t.widget<DecoratedBox>(outer).decoration as BoxDecoration;
      expect((style.border as Border).top.color, green);
      change(() => ids = ['a', 'b']);
      await t.pump();
      expect(find.byKey(const ValueKey('a')), findsOneWidget);
      await t.pumpAndSettle();
      await t.tap(remove('a'));
      await t.pumpAndSettle();
      expect(ids, ['b']);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('delete-only exit settles live reduced motion $suite', (
      t,
    ) async {
      var ids = ['a', 'b'];
      var reduced = false;
      late StateSetter change;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (context, set) {
            change = set;
            return host(
              suite,
              SuiteChipGroup(
                chips: [for (final id in ids) chip(id)],
                onToggle: null,
                onRemoveWithSource: (id, _) => set(() => ids.remove(id)),
              ),
              reduce: reduced,
            );
          },
        ),
      );
      await t.pumpAndSettle();
      await t.tap(remove('a'));
      await t.pump();
      change(() => reduced = true);
      await t.pump();
      await t.pump();
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(find.byKey(const ValueKey('b')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
