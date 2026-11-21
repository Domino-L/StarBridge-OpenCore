// 极品 sheen, user 11-07 option A: still foil; one pass when a tag appears
// (each return to its page too) and on hover; never a whole screen at once.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_diagonal.dart';

import 'marketplace_slice4_test.dart' show preview;

// The page's visibility switches inside one shell: rebuilding the shell
// would start the theme's own transition and muddy the counts.
Widget tags(int count, {ValueListenable<bool>? visible}) => preview(
  ValueListenableBuilder<bool>(
    valueListenable: visible ?? ValueNotifier(true),
    builder: (context, on, _) => TickerMode(
      enabled: on,
      child: Wrap(
        spacing: 8,
        children: [
          for (var i = 0; i < count; i++)
            MarketFoilTag('极品', mono: '${960 + i}', key: ValueKey(i)),
        ],
      ),
    ),
  ),
  AppearanceMode.dark,
);

void main() {
  testWidgets('a tag passes once, then the window stops drawing', (
    tester,
  ) async {
    await tester.pumpWidget(tags(1));
    await tester.pump(); // localizations load before the first real frame
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a screen of tags never sweeps together', (tester) async {
    await tester.pumpWidget(tags(6));
    await tester.pump(); // localizations load before the first real frame
    expect(tester.binding.transientCallbackCount, 2);
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump();
    // The others stayed still; nothing queues up behind the first two.
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('hover always plays, even while two others pass', (
    tester,
  ) async {
    await tester.pumpWidget(tags(4));
    await tester.pump(); // localizations load before the first real frame
    expect(tester.binding.transientCallbackCount, 2);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey(3))));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 3);
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('returning to the page plays the pass again', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(tags(1, visible: visible));
    await tester.pump(); // localizations load before the first real frame
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    visible.value = false;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    visible.value = true;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion stays still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(tags(3));
    await tester.pump(); // localizations load before the first real frame
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
