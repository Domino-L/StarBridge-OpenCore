import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_stage_switch.dart';

Widget _app(String id, int direction, {bool reduced = false}) => MaterialApp(
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en'),
  ),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: LocalHangarStageSwitch(
      shipId: id,
      direction: direction,
      child: Text(id, key: ValueKey('art-$id')),
    ),
  ),
);

void main() {
  testWidgets('the next ship slides in from its side over the last one', (
    tester,
  ) async {
    await tester.pumpWidget(_app('a', 1));
    await tester.pumpWidget(_app('b', 1));
    await tester.pump(LocalHangarStageSwitch.duration ~/ 4);
    // The last picture stays whole beneath while the next one comes in.
    expect(find.byKey(const ValueKey('art-a')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('art-a')),
        matching: find.descendant(
          of: find.byType(LocalHangarStageSwitch),
          matching: find.byType(FadeTransition),
        ),
      ),
      findsNothing,
    );
    final slide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('art-b')),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(slide.position.value.dx, greaterThan(0));
    expect(
      slide.position.value.dx,
      lessThanOrEqualTo(LocalHangarStageSwitch.travel),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('art-a')), findsNothing);
    expect(find.byKey(const ValueKey('art-b')), findsOneWidget);
  });

  testWidgets('going back slides in from the left', (tester) async {
    await tester.pumpWidget(_app('b', 1));
    await tester.pumpWidget(_app('a', -1));
    await tester.pump(LocalHangarStageSwitch.duration ~/ 4);
    final slide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('art-a')),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(slide.position.value.dx, lessThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion cuts straight to the next ship', (tester) async {
    await tester.pumpWidget(_app('a', 1, reduced: true));
    await tester.pumpWidget(_app('b', 1, reduced: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('art-a')), findsNothing);
    expect(find.byKey(const ValueKey('art-b')), findsOneWidget);
    for (final slide in tester.widgetList<SlideTransition>(
      find.descendant(
        of: find.byType(LocalHangarStageSwitch),
        matching: find.byType(SlideTransition),
      ),
    )) {
      expect(slide.position.value, Offset.zero);
    }
  });
}
