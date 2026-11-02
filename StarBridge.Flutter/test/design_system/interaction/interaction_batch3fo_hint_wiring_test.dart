import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/shared/ships/ship_classification_tag.dart';

void main() {
  testWidgets('shared ship hint uses approved tooltip without changing tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShipClassificationTag(label: '地面战斗', color: Colors.red),
        ),
      ),
    );
    final hint = tester.widget<StarBridgeTooltip>(
      find.byType(StarBridgeTooltip),
    );
    expect(hint.message, '地面战斗');
    expect(hint.consumeEscape, isFalse);
    final label = tester.widget<Text>(find.text('地面战斗'));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.fade);
    expect(label.style!.color, Colors.red);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
