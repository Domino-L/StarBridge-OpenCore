import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/icons/avionics_icon.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icons_v2.dart';

void main() {
  testWidgets('every auxiliary semantic uses approved V2 geometry', (
    tester,
  ) async {
    for (final semantic in StandardIconSemantic.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Center(child: StandardIcon(
            semantic,
            size: 18,
            color: Colors.blue,
            semanticLabel: 'Action',
            textDirection: TextDirection.rtl,
          )),
        ),
      );
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
              as AvionicsIconPainter;
      expect(painter.spec, same(catalogBySemantic['Std.${semantic.name}']));
      expect(painter.color, Colors.blue);
      expect(tester.getSize(find.byType(CustomPaint)), const Size(18, 18));
      expect(find.bySemanticsLabel('Action'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('IconTheme size color opacity and direction stay supported', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: IconTheme(
            data: IconThemeData(size: 30, color: Colors.green, opacity: 0.5),
            child: StandardIcon(StandardIconSemantic.arrowForward),
          ),
        ),
      ),
    );
    final painter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
            as AvionicsIconPainter;
    expect(painter.color.a, closeTo(0.5, 0.01));
    expect(painter.mirrored, isTrue);
    expect(tester.getSize(find.byType(CustomPaint)), const Size(30, 30));
  });
}
