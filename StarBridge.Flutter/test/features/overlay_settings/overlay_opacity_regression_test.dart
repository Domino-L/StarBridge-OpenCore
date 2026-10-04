import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  for (final field in ['crosshairOpacity', 'crosshairOutlineOpacity']) {
    testWidgets(
      '$field retains fractional values after integer JSON endpoints',
      (tester) async {
        size(tester, const Size(600, 400));
        final values = <Object?>[];
        var draft = settings({
          'showCrosshair': true,
          'crosshairUseThemeColor': true,
          field: field == 'crosshairOpacity' ? 1 : 0,
        });
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, setState) => OverlayWorkspaceSettingsGroup(
                group: 'crosshair',
                fields: overlayWorkspaceFieldSpecs
                    .where((f) => f.field == field)
                    .toList(),
                settings: draft,
                onChanged: (_, value) => setState(() {
                  draft = draft.withValue(field, value);
                  values.add(value);
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final slider = find.byKey(Key('overlay-field-$field'));
        await tester.tapAt(tester.getCenter(slider));
        await tester.pump();
        expect(values, isNotEmpty);
        expect(
          values.last,
          allOf(isA<double>(), greaterThan(0.2), lessThan(0.8)),
        );
        expect(tester.widget<Slider>(slider).value, values.last);
        // Rebuilding the real draft must not snap the thumb back to its endpoint.
        await tester.drag(slider, const Offset(-30, 0));
        await tester.pump();
        expect(tester.widget<Slider>(slider).value, values.last);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
