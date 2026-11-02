// Test helpers for the executive hangar's preset lists (user decision
// 2026-10-22: times and durations are picked, never typed).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';

const execBeforeOpen = 'exec-before-open-minutes';
const execBeforeClose = 'exec-before-close-minutes';

Finder execPreset(String id) => find.byWidgetPredicate(
  (w) => w is StarBridgeSelectFormField<int> && w.controlKey == Key(id),
);

/// The value a preset list shows (a saved value off the presets included).
int? execPresetShown(WidgetTester t, String id) =>
    t.widget<StarBridgeSelectFormField<int>>(execPreset(id)).initialValue;

/// Opens the list [id] and picks [value].
Future<void> pickExecPreset(WidgetTester t, String id, int value) async {
  final control = find.byKey(Key(id));
  await t.ensureVisible(control);
  await t.pumpAndSettle();
  await t.tap(control);
  await t.pumpAndSettle();
  final row = find.byKey(ValueKey<Object>((id, value)));
  await t.ensureVisible(row);
  await t.tap(row);
  await t.pumpAndSettle();
}
