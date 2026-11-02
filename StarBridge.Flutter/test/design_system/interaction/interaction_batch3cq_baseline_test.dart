import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cn_visual_test.dart' show pixels;
import '../../features/friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  testWidgets('native image toolbar icon button geometry baseline', (t) async {
    await t.pumpWidget(
      scopedApp(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              key: const Key('original'),
              onPressed: () {},
              icon: const StandardIcon(StandardIconSemantic.add, size: 16),
              label: const Text('放大'),
            ),
          ],
        ),
        InteractionSuite.standard,
      ),
    );
    await t.pumpAndSettle();
    final button = find.byKey(const Key('original'));
    final rect = t.getRect(button);
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    // Measured before integration, not an invented compact size.
    debugPrint('3cq native toolbar target=$rect');
  });
  testWidgets('standard action stops all ink on live reduce during hold', (
    t,
  ) async {
    final frame = GlobalKey();
    var calls = 0;
    Widget view(bool reduce) => scopedApp(
      RepaintBoundary(
        key: frame,
        child: StarBridgeActionButton(
          onActivate: (_) => calls++,
          child: const Text('截图'),
        ),
      ),
      InteractionSuite.standard,
      reduce: reduce,
    );
    await t.pumpWidget(view(false));
    await t.pumpAndSettle();
    final gesture = await t.startGesture(t.getCenter(find.text('截图')));
    await t.pump(const Duration(milliseconds: 120));
    await t.pump();
    await t.pumpWidget(view(true));
    await t.pump();
    final stopped = await pixels(t, find.byKey(frame));
    await t.pump(const Duration(milliseconds: 100));
    expect(await pixels(t, find.byKey(frame)), orderedEquals(stopped));
    await gesture.up();
    await t.pumpAndSettle();
    expect(calls, 1);
  });
}
