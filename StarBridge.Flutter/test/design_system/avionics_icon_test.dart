import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/menu_bridge_glyph.dart';
import 'package:starbridge_flutter/design_system/icons/window_control_icon.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/icons/avionics_icon.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icons_v2.dart';

void main() {
  test('catalog covers all four production semantic families exactly once', () {
    final references = catalog.expand((s) => s.replaces).toList();
    expect(references.toSet().length, references.length);
    expect(catalogByKey.length, catalog.length);
    for (final reference in [
      ...StarBridgeIconSemantic.values.map((s) => 'SB.${s.name}'),
      ...StandardIconSemantic.values.map((s) => 'Std.${s.name}'),
      ...MenuGlyph.values.map((s) => 'Menu.${s.name}'),
      ...WindowGlyph.values.map((s) => 'Window.${s.name}'),
    ]) {
      expect(catalogBySemantic, contains(reference));
    }
    expect(catalogBySemantic['Menu.ship']!.key, 'ship');
    expect(catalogBySemantic['SB.hangar']!.key, 'hangar');
    expect(catalogBySemantic['Menu.location']!.key, 'location');
  });
  test('every V2 glyph paints at compact standard and display sizes', () {
    for (final spec in catalog) {
      for (final size in [14.0, 16.0, 20.0, 24.0, 32.0]) {
        final recorder = ui.PictureRecorder();
        AvionicsIconPainter(
          spec,
          Colors.white,
        ).paint(Canvas(recorder), Size.square(size));
        recorder.endRecording().dispose();
      }
    }
  });
  testWidgets('menu and window wrappers use V2 without changing extent', (
    tester,
  ) async {
    for (final glyph in MenuGlyph.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: MenuGlyphView(glyph)),
        ),
      );
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
              as AvionicsIconPainter;
      expect(painter.spec, same(catalogBySemantic['Menu.${glyph.name}']));
      expect(tester.getSize(find.byType(CustomPaint)), const Size(20, 20));
    }
    for (final glyph in WindowGlyph.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: WindowControlIcon(glyph)),
        ),
      );
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
              as AvionicsIconPainter;
      expect(painter.spec, same(catalogBySemantic['Window.${glyph.name}']));
      expect(tester.getSize(find.byType(CustomPaint)), const Size(15, 15));
    }
  });
}
