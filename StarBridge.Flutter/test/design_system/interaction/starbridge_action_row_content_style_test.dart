// StarBridgeActionRow.inheritContentStyle: rows migrated from a bare InkWell
// keep their content's own text and icon style in every suite; rows that do
// not opt in keep the pressable's row foreground as before.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

import 'interaction_batch3i_test.dart' show scopedApp;

const _outer = TextStyle(fontSize: 11, color: Color(0xFFAA3355), height: 1.2);
const _icon = IconThemeData(color: Color(0xFF33AA55), size: 13);

Widget _row({required bool inherit}) => DefaultTextStyle(
  style: _outer,
  child: IconTheme(
    data: _icon,
    child: StarBridgeActionRow(
      inheritContentStyle: inherit,
      onActivate: (_, _) {},
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text('content'), Icon(Icons.circle)],
      ),
    ),
  ),
);

TextStyle _textStyle(WidgetTester tester) => tester
    .widget<RichText>(
      find.descendant(
        of: find.text('content'),
        matching: find.byType(RichText),
      ),
    )
    .text
    .style!;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: opted-in content keeps its own style', (
      tester,
    ) async {
      await tester.pumpWidget(scopedApp(_row(inherit: true), suite));
      await tester.pumpAndSettle();
      final style = _textStyle(tester);
      expect(style.fontSize, 11);
      expect(style.color, _outer.color);
      expect(style.height, 1.2);
      final icon = tester.widget<RichText>(
        find.descendant(of: find.byType(Icon), matching: find.byType(RichText)),
      );
      expect(icon.text.style!.color, _icon.color);
      expect(icon.text.style!.fontSize, 13);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${suite.name}: rows that do not opt in are unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(scopedApp(_row(inherit: false), suite));
      await tester.pumpAndSettle();
      expect(_textStyle(tester).color, isNot(_outer.color));
      expect(tester.takeException(), isNull);
    });
  }
}
