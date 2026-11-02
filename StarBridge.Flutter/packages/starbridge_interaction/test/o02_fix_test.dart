// Codex O02 audit (2026-10-09), package side: popover close source
// (O02-03), no actions while leaving (O02-04), window-bounded height
// (O02-05), attachment focus with an in-place list (O02-06).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

const _animated = [InteractionSuite.rail, InteractionSuite.scan, InteractionSuite.glow];

Widget _host(InteractionSuite suite, Widget child) => InteractionScope(
  data: InteractionData(suite: suite, palette: palette),
  child: MaterialApp(home: Scaffold(body: child)),
);

final _popKey = GlobalKey<SuitePopoverState>();

/// The × icon inside the chip for file [id].
Finder _remove(String id) => find.descendant(
  of: find.ancestor(of: find.text('$id.png'), matching: find.byType(Row)).first,
  matching: find.byIcon(Icons.close),
);

Widget _pop(InteractionSuite suite, {required List<String> log, Alignment where = Alignment.topCenter, Widget? tall}) => _host(
  suite,
  Align(
    alignment: where,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: SuitePopover(
        key: _popKey,
        anchorBuilder: (context, open) => const Text('房主'),
        contentBuilder: (context, close) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SuitePressable(
              kind: PressableKind.secondary,
              onActivate: (s) {
                log.add('first:${s.name}');
                close(s);
              },
              child: const Text('发私信'),
            ),
            ?tall,
            SuitePressable(
              kind: PressableKind.secondary,
              onActivate: (s) => log.add('last:${s.name}'),
              child: const Text('查看机库'),
            ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  group('O02-03 popover: close carries the action source', () {
    for (final suite in _animated) {
      testWidgets('${suite.name}: Enter on an inner action closes in the same frame; a click plays the exit', (t) async {
        final log = <String>[];
        await t.pumpWidget(_pop(suite, log: log));
        await t.tap(find.text('房主'));
        await t.pumpAndSettle();
        // Focus moved to the first inner action on open.
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(log, ['first:keyboard']);
        expect(find.text('发私信'), findsNothing, reason: 'keyboard close is instant');
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'popover-anchor');

        await t.tap(find.text('房主'));
        await t.pumpAndSettle();
        await t.tap(find.text('发私信'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        expect(log.last, 'first:pointer');
        expect(find.text('发私信'), findsOneWidget, reason: 'pointer close keeps its exit');
        await t.pumpAndSettle();
        expect(find.text('发私信'), findsNothing);
      });
    }
  });

  group('O02-03 popover: close() without a source uses what triggered it', () {
    for (final suite in _animated) {
      testWidgets('${suite.name}: key → instant; click → exit', (t) async {
        await t.pumpWidget(_host(suite, Center(child: SuitePopover(
          anchorBuilder: (c, o) => const Text('anchor'),
          contentBuilder: (c, close) => SuitePressable(
            kind: PressableKind.secondary,
            onPressed: close,
            child: const Text('inner close'),
          ),
        ))));
        await t.tap(find.text('anchor'));
        await t.pumpAndSettle();
        Focus.of(t.element(find.text('inner close'))).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(find.text('inner close'), findsNothing);
        await t.tap(find.text('anchor'));
        await t.pumpAndSettle();
        await t.tap(find.text('inner close'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        expect(find.text('inner close'), findsOneWidget);
        await t.pumpAndSettle();
        expect(find.text('inner close'), findsNothing);
      });
    }
  });

  group('O02-04 popover: nothing inside acts while it leaves', () {
    for (final suite in _animated) {
      testWidgets('${suite.name}: taps, focus and semantics are off while closing; reopening restores them', (t) async {
        final handle = t.ensureSemantics();
        final log = <String>[];
        await t.pumpWidget(_pop(suite, log: log));
        await t.tap(find.text('房主'));
        await t.pumpAndSettle();
        _popKey.currentState!.close();
        await t.pump();
        await t.pump(const Duration(milliseconds: 16));
        expect(find.text('查看机库'), findsOneWidget, reason: 'the exit is still painted');
        await t.tap(find.text('查看机库'), warnIfMissed: false);
        await t.pump();
        expect(log, isEmpty, reason: 'pointer');
        expect(find.semantics.byLabel('查看机库'), findsNothing, reason: 'screen reader');
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(log.where((e) => e.startsWith('last')), isEmpty, reason: 'keyboard');
        // Reopen mid-exit: one panel, usable again.
        _popKey.currentState!.open();
        await t.pumpAndSettle();
        expect(find.text('查看机库'), findsOneWidget);
        await t.tap(find.text('查看机库'));
        await t.pump();
        expect(log.where((e) => e == 'last:pointer'), hasLength(1));
        handle.dispose();
      });
    }
  });

  group('O02-05 popover: bounded by the window', () {
    for (final where in [Alignment.bottomCenter, Alignment.topCenter, Alignment.bottomLeft, Alignment.topRight, Alignment.centerLeft]) {
      testWidgets('400×320 window, anchor at $where: panel inside 8 px; long content scrolls to every action', (t) async {
        t.view.physicalSize = const Size(400, 320);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final log = <String>[];
        await t.pumpWidget(_pop(InteractionSuite.rail, log: log, where: where, tall: const SizedBox(height: 400)));
        await t.tap(find.text('房主'));
        await t.pumpAndSettle();
        final panel = t.getRect(find.ancestor(of: find.byType(SingleChildScrollView), matching: find.byType(Container)).first);
        expect(panel.top, greaterThanOrEqualTo(8 - 0.01));
        expect(panel.bottom, lessThanOrEqualTo(312 + 0.01));
        expect(panel.left, greaterThanOrEqualTo(8 - 0.01));
        expect(panel.right, lessThanOrEqualTo(392 + 0.01));
        // First action reachable as is; the last one by keyboard (traversal
        // scrolls it into view) and then by pointer.
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(log, ['last:keyboard']);
        await t.tap(find.text('查看机库'));
        await t.pump();
        expect(log.last, 'last:pointer');
      });
    }

    testWidgets('a narrow window narrows the panel', (t) async {
      t.view.physicalSize = const Size(200, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_pop(InteractionSuite.glow, log: []));
      await t.tap(find.text('房主'));
      await t.pumpAndSettle();
      final panel = t.getRect(find.ancestor(of: find.byType(SingleChildScrollView), matching: find.byType(Container)).first);
      expect(panel.left, greaterThanOrEqualTo(8 - 0.01));
      expect(panel.right, lessThanOrEqualTo(192 + 0.01));
    });
  });

  group('O02-06 attachments: one list changed in place', () {
    List<SuiteAttachment> files(List<String> ids) => [
      for (final id in ids) SuiteAttachment(id: id, name: '$id.png', sizeLabel: '1 KB'),
    ];

    Future<(List<SuiteAttachment>, StateSetter, FocusNode)> tray(WidgetTester t, List<String> ids) async {
      final list = files(ids); // the same list object throughout, as the store does
      final input = FocusNode(debugLabel: 'input');
      addTearDown(input.dispose);
      late StateSetter set;
      await t.pumpWidget(_host(InteractionSuite.scan, StatefulBuilder(builder: (context, s) {
        set = s;
        return Column(
          children: [
            SuiteAttachmentTray(
              attachments: list,
              fallbackFocus: input,
              onRemove: (id) => s(() => list.removeWhere((f) => f.id == id)),
              onRetry: (_) {},
            ),
            Focus(focusNode: input, child: const SizedBox(width: 10, height: 10)),
          ],
        );
      })));
      return (list, set, input);
    }

    Future<void> deleteFocused(WidgetTester t, String id) async {
      Focus.of(t.element(_remove(id))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pump();
      await t.pump();
    }

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    for (final (ids, target, expected) in [
      (['a', 'b', 'c'], 'a', 'attachment-b'),
      (['a', 'b', 'c'], 'b', 'attachment-c'),
      (['a', 'b', 'c'], 'c', 'attachment-b'),
      (['a'], 'a', 'input'),
    ]) {
      testWidgets('delete $target of $ids → focus $expected', (t) async {
        await tray(t, ids);
        await deleteFocused(t, target);
        expect(focused(), expected);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('two removals before a frame: focus goes to what still exists', (t) async {
      final (list, set, _) = await tray(t, ['a', 'b', 'c']);
      Focus.of(t.element(_remove('a'))).requestFocus();
      await t.pump();
      set(() => list.removeWhere((f) => f.id == 'a'));
      await t.pump(); // focus would move to b after this frame
      set(() => list.removeWhere((f) => f.id == 'b'));
      await t.pump();
      await t.pump();
      expect(focused(), 'attachment-c');
      expect(t.takeException(), isNull);
    });

    testWidgets('clearing everything falls back to the input', (t) async {
      final (list, set, _) = await tray(t, ['a', 'b']);
      Focus.of(t.element(_remove('b'))).requestFocus();
      await t.pump();
      set(list.clear);
      await t.pump();
      await t.pump();
      expect(focused(), 'input');
    });

    testWidgets('progress and retry updates in place keep focus where it is', (t) async {
      final (list, set, _) = await tray(t, ['a', 'b']);
      Focus.of(t.element(_remove('b'))).requestFocus();
      await t.pump();
      final before = FocusManager.instance.primaryFocus;
      set(() => list[0] = list[0].copyWith(phase: AttachmentPhase.uploading, progress: 0.4));
      await t.pump();
      set(() => list[0] = list[0].copyWith(phase: AttachmentPhase.done, progress: 1));
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(before));
    });
  });

  group('page switch keeps the new page mounted through its entrance', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: the page state is created once', (t) async {
        var page = 'a';
        late StateSetter set;
        _Probe.created = 0;
        await t.pumpWidget(_host(suite, StatefulBuilder(builder: (context, s) {
          set = s;
          return SuiteContentSwitcher(child: _Probe(key: ValueKey(page)));
        })));
        expect(_Probe.created, 1);
        set(() => page = 'b');
        await t.pumpAndSettle();
        expect(_Probe.created, 2, reason: 'one new state for the new page, not two');
      });
    }
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});
  static int created = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.created++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}
