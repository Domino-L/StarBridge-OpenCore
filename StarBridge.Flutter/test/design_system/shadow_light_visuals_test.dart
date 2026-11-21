import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/frame_governor.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/surfaces/light_visual_shadow_scope.dart';
import 'package:starbridge_flutter/design_system/surfaces/starbridge_surface.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

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
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets(
      '${mode.name} surface shadows disappear and restore without changing tokens',
      (tester) async {
        final tokens = FutureRestraintStyle.resolve(mode);
        const roles = [
          SurfaceRole.panel,
          SurfaceRole.raised,
          SurfaceRole.floating,
        ];
        await pumpLightVisuals(
          tester,
          lightVisualsApp(
            Column(
              children: [
                for (final role in roles)
                  StarBridgeSurface(
                    key: ValueKey(role),
                    role: role,
                    child: const Text('surface'),
                  ),
              ],
            ),
            mode: mode,
          ),
        );
        List<BoxShadow> shadows(SurfaceRole role) =>
            (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: find.byKey(ValueKey(role)),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .boxShadow!;
        for (final role in roles) {
          expect(shadows(role), tokens.surfaces.resolve(role).shadows);
        }
        light.value = true;
        await tester.pump();
        for (final role in roles) {
          expect(shadows(role), isEmpty);
        }
        expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
        expect(fractionalOpacityLayers(tester), isEmpty);
        light.value = false;
        await tester.pump();
        for (final role in roles) {
          expect(shadows(role), tokens.surfaces.resolve(role).shadows);
        }
      },
    );
  }
  testWidgets('scoped tooltip drops only shadows and retains child state', (
    tester,
  ) async {
    late TooltipThemeData data;
    final key = GlobalKey<TooltipState>();
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        LightVisualShadowScope(
          child: Builder(
            builder: (context) {
              data = TooltipTheme.of(context);
              return Center(
                child: Tooltip(
                  key: key,
                  message: 'tip',
                  child: const Text('target'),
                ),
              );
            },
          ),
        ),
      ),
    );
    final original = data.decoration! as BoxDecoration;
    expect(original.boxShadow, isNotEmpty);
    final state = key.currentState;
    light.value = true;
    await tester.pump();
    expect(key.currentState, same(state));
    final reduced = data.decoration! as BoxDecoration;
    expect(reduced.boxShadow, isEmpty);
    expect(reduced.color, original.color);
    expect(reduced.border, original.border);
    expect(reduced.borderRadius, original.borderRadius);
    key.currentState!.ensureTooltipVisible();
    await tester.pumpAndSettle();
    // Box shadows paint into a Picture; neither mode adds a filter layer.
    expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
    light.value = false;
    await tester.pump();
    expect((data.decoration! as BoxDecoration).boxShadow, original.boxShadow);
    await pumpLightVisuals(tester, const SizedBox());
  });
}
