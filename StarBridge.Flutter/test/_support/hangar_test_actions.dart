import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_holo_choice.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

Finder hangarChoiceAncestor(Finder target) =>
    find.ancestor(of: target, matching: find.byType(OrganizationHoloChoice));

OrganizationHoloChoice hangarChoice(WidgetTester tester, String key) => tester
    .widget<OrganizationHoloChoice>(hangarChoiceAncestor(find.byKey(Key(key))));

FocusNode hangarChoiceFocus(WidgetTester tester, Finder target) => tester
    .widget<Focus>(
      find
          .descendant(
            of: hangarChoiceAncestor(target),
            matching: find.byWidgetPredicate(
              (widget) => widget is Focus && widget.focusNode != null,
            ),
          )
          .first,
    )
    .focusNode!;

FocusNode hangarControlFocus(WidgetTester tester, Finder target) {
  if (hangarChoiceAncestor(target).evaluate().isNotEmpty) {
    return hangarChoiceFocus(tester, target);
  }
  return switch (tester.widget(target)) {
    ButtonStyleButton button => button.focusNode!,
    IconButton button => button.focusNode!,
    SuitePressable button =>
      button.focusNode ??
          tester
              .widget<FocusableActionDetector>(
                find
                    .descendant(
                      of: target,
                      matching: find.byType(FocusableActionDetector),
                    )
                    .first,
              )
              .focusNode!,
    final widget => throw StateError('Unsupported hangar focus target $widget'),
  };
}

Future<void> activateHangarWithKeyboard(
  WidgetTester tester,
  Finder target,
) async {
  await tester.ensureVisible(target);
  final node = hangarControlFocus(tester, target);
  for (var i = 0; !node.hasPrimaryFocus && i < 100; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(node.hasPrimaryFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

// Advance finite UI motion without waiting for deliberately pending business
// reads or writes. Those operations retain their original gates and assertions.
Future<void> _activate(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> openHangarDetails(
  WidgetTester tester,
  Finder entry, {
  Future<void> Function(Finder)? activate,
  VoidCallback? onStage,
}) async {
  final action = activate ?? (target) => _activate(tester, target);
  await tester.ensureVisible(entry.first);
  await tester.pumpAndSettle();
  await action(entry);
  expect(find.byKey(const Key('hangar-stage')), findsOneWidget);
  onStage?.call();
  await action(find.byKey(const Key('hangar-stage-details')));
}

Future<void> backToHangarWall(WidgetTester tester) async {
  await _activate(tester, find.byKey(const Key('hangar-stage-back')));
  expect(find.byKey(const Key('hangar-stage')), findsNothing);
}
