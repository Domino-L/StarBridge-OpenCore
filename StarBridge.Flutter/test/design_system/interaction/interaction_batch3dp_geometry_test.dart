import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';

import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dp_test.dart';

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${suite.name}/$scale checkbox titles keep original native leading geometry',
        (t) async {
          fixture.size(t, const Size(960, 900));
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final p = SharingProbe();
          await openSharing(t, p.dialog(), suite);
          final target = find.byKey(const Key('community-sharing-1'));
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          final adapter = t.widget<StarBridgeCheckboxTile>(target);
          final nativeLabel = adapter.label;
          final title = find.descendant(
            of: target,
            matching: find.text(nativeLabel),
          );
          final titleOffset = t.getTopLeft(title) - t.getTopLeft(target);
          final height = t.getSize(target).height;
          final width = t.getSize(target).width;
          await t.pumpWidget(const SizedBox());
          final nativeKey = GlobalKey();
          await t.pumpWidget(
            fixture.scopedApp(
              SizedBox(
                width: width,
                child: CheckboxListTile(
                  key: nativeKey,
                  value: true,
                  onChanged: (_) {},
                  title: Text(nativeLabel),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final native = find.byKey(nativeKey);
          final nativeOffset =
              t.getTopLeft(
                find.descendant(of: native, matching: find.text(nativeLabel)),
              ) -
              t.getTopLeft(native);
          expect(titleOffset.dx, closeTo(nativeOffset.dx, .01));
          expect(titleOffset.dy, closeTo(nativeOffset.dy, .01));
          expect(height, closeTo(t.getSize(native).height, .01));
        },
      );
    }
  }
}
