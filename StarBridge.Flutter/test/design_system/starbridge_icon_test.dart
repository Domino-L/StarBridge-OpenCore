import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon_painter.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon_set.dart';

void main() {
  testWidgets('all semantic icons render at each optical master size', (
    tester,
  ) async {
    const sizes = [16.0, 20.0, 24.0];
    await tester.pumpWidget(
      _harness(
        Wrap(
          children: [
            for (final size in sizes)
              for (final semantic in StarBridgeIconSemantic.values)
                StarBridgeIcon(semantic, size: size),
          ],
        ),
      ),
    );

    expect(
      find.byType(StarBridgeIcon),
      findsNWidgets(sizes.length * StarBridgeIconSemantic.values.length),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('IconTheme controls default size, color, and opacity', (
    tester,
  ) async {
    const themeColor = Color(0xFF4EA9BC);
    await tester.pumpWidget(
      _harness(
        const StarBridgeIcon(StarBridgeIconSemantic.home),
        iconTheme: const IconThemeData(
          size: 16,
          color: themeColor,
          opacity: 0.5,
        ),
      ),
    );

    expect(tester.getSize(find.byType(CustomPaint)), const Size.square(16));
    final painter = _onlyPainter(tester);
    expect(painter.color, themeColor.withValues(alpha: 0.5));
  });

  testWidgets('explicit size and color override IconTheme values', (
    tester,
  ) async {
    const explicitColor = Color(0xFF8BD8E5);
    await tester.pumpWidget(
      _harness(
        const StarBridgeIcon(
          StarBridgeIconSemantic.scene,
          size: 24,
          color: explicitColor,
        ),
        iconTheme: const IconThemeData(size: 16, color: Color(0xFFAA3344)),
      ),
    );

    expect(tester.getSize(find.byType(CustomPaint)), const Size.square(24));
    expect(_onlyPainter(tester).color, explicitColor);
  });

  testWidgets('icons are decorative unless given an explicit label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(const StarBridgeIcon(StarBridgeIconSemantic.home)),
    );
    expect(find.bySemanticsLabel('StarBridge home'), findsNothing);

    await tester.pumpWidget(
      _harness(
        const StarBridgeIcon(
          StarBridgeIconSemantic.home,
          semanticLabel: 'StarBridge home',
        ),
      ),
    );
    expect(find.bySemanticsLabel('StarBridge home'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('directional glyphs mirror in RTL and fixed glyphs do not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const Row(
          children: [
            StarBridgeIcon(StarBridgeIconSemantic.forward, key: Key('forward')),
            StarBridgeIcon(StarBridgeIconSemantic.home, key: Key('home')),
            StarBridgeIcon(
              StarBridgeIconSemantic.login,
              key: Key('forced-ltr'),
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
        direction: TextDirection.rtl,
      ),
    );

    expect(_painterFor(tester, const Key('forward')).mirrored, isTrue);
    expect(_painterFor(tester, const Key('home')).mirrored, isFalse);
    expect(_painterFor(tester, const Key('forced-ltr')).mirrored, isFalse);
  });

  test('brand signatures are restricted to meaningful semantics', () {
    final trail = <StarBridgeIconSemantic>{};
    final junction = <StarBridgeIconSemantic>{};
    for (final semantic in StarBridgeIconSemantic.values) {
      switch (StarBridgeIconSet.resolve(semantic).signature) {
        case StarBridgeIconSignature.none:
          break;
        case StarBridgeIconSignature.trail:
          trail.add(semantic);
          break;
        case StarBridgeIconSignature.junction:
          junction.add(semantic);
          break;
      }
    }

    expect(trail, isEmpty);
    expect(junction, {
      StarBridgeIconSemantic.home,
      StarBridgeIconSemantic.scene,
    });
  });
}

Widget _harness(
  Widget child, {
  IconThemeData iconTheme = const IconThemeData(
    size: 20,
    color: Color(0xFFE7EEF2),
  ),
  TextDirection direction = TextDirection.ltr,
}) {
  return Directionality(
    textDirection: direction,
    child: DefaultTextStyle(
      style: const TextStyle(color: Color(0xFFE7EEF2)),
      child: IconTheme(
        data: iconTheme,
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

StarBridgeIconPainter _onlyPainter(WidgetTester tester) {
  return tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
      as StarBridgeIconPainter;
}

StarBridgeIconPainter _painterFor(WidgetTester tester, Key key) {
  final paint = find.descendant(
    of: find.byKey(key),
    matching: find.byType(CustomPaint),
  );
  return tester.widget<CustomPaint>(paint).painter! as StarBridgeIconPainter;
}
