import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3cc_test.dart' show Fixture, mount;

Future<void> _chooseByKeyboard(WidgetTester t, String id) async {
  const command = Key('menu-workspace-section-command');
  final row = find.byWidgetPredicate(
    (widget) => widget is StarBridgeActionRow && widget.controlKey == command,
  );
  expect(row, findsOneWidget);
  await t.ensureVisible(row);
  await frames(t);
  final owner = t.widget<StarBridgeActionRow>(row).focusNode;
  expect(owner, isNotNull);
  expect(owner!.canRequestFocus, isTrue);
  final anchor = find.ancestor(
    of: row,
    matching: find.byType(StarBridgeMenuAnchor),
  );
  expect(anchor, findsOneWidget);
  final configuration = t.widget<StarBridgeMenuAnchor>(anchor);
  final raw = find.descendant(of: anchor, matching: find.byType(RawMenuAnchor));
  expect(raw, findsOneWidget);
  final controller = t.widget<RawMenuAnchor>(raw).controller;
  expect(controller, isNotNull);
  expect(controller.isOpen, isFalse);

  // The public node identifies the actual destination; it is never requested
  // directly. This locks down traversal as well as Enter delivery.
  var reached = false;
  for (var step = 0; step < 64; step++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.pump();
    if (identical(FocusManager.instance.primaryFocus, owner)) {
      reached = true;
      break;
    }
  }
  expect(
    reached,
    isTrue,
    reason: 'Real Tab must reach the current compact section selector.',
  );
  expect(FocusManager.instance.primaryFocus, same(owner));
  expect(owner.hasPrimaryFocus, isTrue);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
  expect(controller.isOpen, isTrue);

  final menu = find.byWidgetPredicate(
    (widget) =>
        widget is SuiteSurfaceTransition && widget.kind == SurfaceKind.menu,
  );
  expect(menu, findsOneWidget);
  expect(t.widget<SuiteSurfaceTransition>(menu).animation.value, 1);
  final item = find.byKey(ValueKey<Object>(('menu-workspace-section', id)));
  expect(item, findsOneWidget);
  final control = t.widget(item);
  final FocusNode? target;
  if (control is MenuItemButton) {
    expect(control.onPressed, isNotNull);
    target = control.focusNode;
  } else if (control is SuitePressable) {
    expect(control.onActivate, isNotNull);
    target = control.focusNode;
  } else {
    throw StateError(
      'The section must expose its actual menu row focus owner.',
    );
  }
  expect(target, isNotNull);
  expect(target!.canRequestFocus, isTrue);

  var reachedEntry = identical(FocusManager.instance.primaryFocus, target);
  for (
    var step = 0;
    step < configuration.entries.length && !reachedEntry;
    step++
  ) {
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.pump();
    reachedEntry = identical(FocusManager.instance.primaryFocus, target);
  }
  expect(reachedEntry, isTrue);
  expect(target.hasPrimaryFocus, isTrue);
  expect(controller.isOpen, isTrue);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await frames(t);
  expect(menu, findsNothing);

  final field = find.byKey(ValueKey('menu-section-$id'));
  expect(field, findsOneWidget);
  expect(t.widget<StarBridgeSelectFormField<String>>(field).initialValue, id);
  expect(t.state<FormFieldState<String>>(field).value, id);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final width in [430.0, 1100.0]) {
      testWidgets(
        '$suite real Tab section selector preserves draft and independent editor at $width',
        (t) async {
          final h = Fixture();
          try {
            final state = await mount(t, h, suite, width: width);
            expect(h.port.reads, 1);
            final confirmedRevision = h.port.value.revision;
            // Preserve the original 3cc real-owner dirty setup; all section
            // selection still goes through actual Tab/Arrow/Enter.
            h.draft.change({'showClock': false});
            await frames(t);
            final settingsBefore = Map<String, Object?>.of(h.draft.settings);
            expect(h.draft.dirty, isTrue);
            expect(h.port.writes, 0);

            await _chooseByKeyboard(t, 'shortcuts');
            await t.enterText(
              find.byKey(const Key('independent-editor')),
              'local unsaved note',
            );
            await t.pump();
            final input = t
                .widget<TextField>(find.byKey(const Key('independent-editor')))
                .controller;

            await _chooseByKeyboard(t, 'browser');
            expect(h.draft.settings, settingsBefore);
            expect(h.port.writes, 0);
            await _chooseByKeyboard(t, 'shortcuts');

            expect(
              t
                  .widget<TextField>(
                    find.byKey(const Key('independent-editor')),
                  )
                  .controller,
              same(input),
            );
            expect(state.input.text, 'local unsaved note');
            expect(h.draft.settings, settingsBefore);
            expect(h.draft.settings['showClock'], isFalse);
            expect(h.draft.dirty, isTrue);
            expect(h.draft.canUndo, isTrue);
            expect(h.draft.busy, isFalse);
            expect(h.draft.failed, isFalse);
            expect(h.port.reads, 1);
            expect(h.port.writes, 0);
            expect(h.port.value.revision, confirmedRevision);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}
