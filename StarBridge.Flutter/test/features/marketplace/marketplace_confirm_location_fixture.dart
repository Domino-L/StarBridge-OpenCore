import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Existing submission/motion cases must now make the required location choice.
Future<void> chooseConfirmLocation(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('market-confirm-location')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fixture location').last);
  await tester.pumpAndSettle();
}
