import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/frame_governor.dart';
import 'package:starbridge_flutter/design_system/surfaces/light_visual_shadow_scope.dart';
import 'package:starbridge_flutter/design_system/surfaces/light_visual_text.dart';

import '../support/light_visuals_test_support.dart';

void main() {
  late ValueNotifier<bool> light;
  setUp(() {
    light = ValueNotifier(false);
    debugLightVisualsOverride = light;
  });
  tearDown(() {
    debugLightVisualsOverride = null;
    light.dispose();
  });

  TextOverflow overflow(WidgetTester tester) => tester
      .renderObject<RenderParagraph>(find.text('a long name that overflows'))
      .overflow;

  Widget label() => SizedBox(
    width: 40,
    child: Builder(
      builder: (context) => Text(
        'a long name that overflows',
        maxLines: 1,
        softWrap: false,
        overflow: fadeOverflow(context),
      ),
    ),
  );

  testWidgets('pages cut overflowing text with an ellipsis while a game runs', (
    tester,
  ) async {
    await pumpLightVisuals(
      tester,
      lightVisualsApp(LightVisualShadowScope(child: label())),
    );
    expect(overflow(tester), TextOverflow.fade);
    light.value = true;
    await tester.pump();
    expect(overflow(tester), TextOverflow.ellipsis);
    light.value = false;
    await tester.pump();
    expect(overflow(tester), TextOverflow.fade);
  });

  testWidgets('outside the page scope text keeps its fade', (tester) async {
    light.value = true;
    await pumpLightVisuals(tester, lightVisualsApp(label()));
    expect(overflow(tester), TextOverflow.fade);
  });
}
