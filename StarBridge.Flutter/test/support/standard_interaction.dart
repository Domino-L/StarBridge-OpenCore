import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionScope, InteractionSuite;

/// Page tests written against the "standard" interaction suite pin it
/// explicitly. Since 0.7.3 the default is "scan" (user: "把所有人的交互都换成扫描");
/// each page group also keeps a few scan smoke tests, and each suite's own
/// look and behaviour is covered under test/design_system/interaction.
InMemoryAppPreferences standardInteraction([
  AppPreferences base = AppPreferences.defaults,
]) => InMemoryAppPreferences(
  initial: base.copyWith(interactionStyle: InteractionStyle.standard),
);

/// Sets [style] on preferences a test already holds (or on new defaults).
Future<InMemoryAppPreferences> pinInteraction(
  InMemoryAppPreferences? preferences, [
  InteractionStyle style = InteractionStyle.standard,
]) async {
  final value = preferences ?? InMemoryAppPreferences();
  await value.setInteractionStyle(style);
  return value;
}

/// The page under [finder] really runs the scan suite.
void expectScanSuite(WidgetTester tester, Finder finder) => expect(
  InteractionScope.of(tester.element(finder.first)).suite,
  InteractionSuite.scan,
);

/// Reads a control by what a person or screen reader sees (its semantics),
/// whatever widget type the suite builds it from.
void expectButtonState(
  WidgetTester tester,
  Finder finder, {
  required bool enabled,
}) {
  final data = tester.getSemantics(finder).getSemanticsData();
  final flags = data.flagsCollection;
  expect(flags.isButton, isTrue, reason: 'exposed as a button');
  expect(
    flags.isEnabled,
    enabled ? Tristate.isTrue : Tristate.isFalse,
    reason: enabled ? 'button is enabled' : 'button is disabled',
  );
  expect(
    data.hasAction(SemanticsAction.tap),
    enabled,
    reason: enabled ? 'offers a tap action' : 'offers no tap action',
  );
  if (enabled) {
    // Semantics alone would pass a button hidden behind IgnorePointer or
    // another layer (review CX-ISCAN-DEFAULT-073-REVIEW P3).
    expect(finder.hitTestable(), findsWidgets, reason: 'can be clicked');
  }
}
