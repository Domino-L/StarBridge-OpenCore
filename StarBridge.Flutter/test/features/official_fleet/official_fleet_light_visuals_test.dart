import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/frame_governor.dart';
import 'package:starbridge_flutter/features/common/organization_holo_art.dart';
import 'package:starbridge_flutter/features/common/organization_holo_deck.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_holo_header.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_holo_layers.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_screen_switch.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_section_rail.dart';

import '../../support/light_visuals_test_support.dart';

void main() {
  // Use bytes for the sealed production art type; the empty image falls back
  // locally without touching remote sources.
  final art = OrganizationHoloArt.bytes(Uint8List(0));
  late ValueNotifier<bool> light;
  setUp(() {
    light = ValueNotifier(false);
    debugLightVisualsOverride = light;
  });
  tearDown(() {
    debugLightVisualsOverride = null;
    light.dispose();
  });
  testWidgets('light mode removes both reflection masks and restores them', (
    tester,
  ) async {
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        Column(
          children: [
            SizedBox(
              width: 200,
              height: 80,
              child: OfficialFleetHoloMirror(art, light: false),
            ),
            SizedBox(
              width: 200,
              height: 80,
              child: OfficialFleetDeckMirror(art),
            ),
          ],
        ),
      ),
    );
    expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(2));
    light.value = true;
    await tester.pump();
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
    light.value = false;
    await tester.pump();
    expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(2));
  });
  testWidgets('light ghost uses its completed outline during entry', (
    tester,
  ) async {
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        const Center(
          child: OfficialFleetHoloGhostSid(
            'CX',
            size: 48,
            light: false,
            reveal: AlwaysStoppedAnimation(.35),
            accent: Colors.teal,
          ),
        ),
      ),
    );
    expect(tester.layers.whereType<ShaderMaskLayer>(), isNotEmpty);
    light.value = true;
    await tester.pump();
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
    expect(fractionalOpacityLayers(tester), isEmpty);
  });
  testWidgets('screen switch uses the destination immediately without layers', (
    tester,
  ) async {
    Widget screen(bool lower) => lightVisualsApp(
      OfficialFleetScreenSwitch(
        lower: lower,
        upper: (_) => const Center(child: Text('upper')),
        lowerBuilder: (_) => const Center(child: Text('lower')),
        banner: art,
        bannerHeight: 200,
      ),
    );
    await pumpLightVisuals(tester, screen(false));
    await pumpLightVisuals(tester, screen(true));
    await tester.pump(const Duration(milliseconds: 210));
    expect(fractionalOpacityLayers(tester), isNotEmpty);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isNotEmpty);
    light.value = true;
    await tester.pump();
    expect(find.text('lower'), findsOneWidget);
    expect(find.text('upper'), findsNothing);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
    expect(fractionalOpacityLayers(tester), isEmpty);
    expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
    expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
    // Back to the full look: the switch stays finished, not half-way, and the
    // lower screen still takes input.
    light.value = false;
    await tester.pump();
    expect(find.text('lower'), findsOneWidget);
    expect(fractionalOpacityLayers(tester), isEmpty);
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(
              of: find.text('lower'),
              matching: find.byType(IgnorePointer),
            ),
          )
          .any((w) => w.ignoring),
      isFalse,
    );
    light.value = true;
    await tester.pump();
    await pumpLightVisuals(tester, screen(false));
    expect(find.text('upper'), findsOneWidget);
    expect(fractionalOpacityLayers(tester), isEmpty);
  });
  testWidgets(
    'header entrance settles while a game runs and restores full rendering',
    (tester) async {
      await pumpLightVisuals(
        tester,
        lightVisualsApp(
          const SingleChildScrollView(
            child: OfficialFleetHoloHeader(
              deck: OrganizationHoloDeck(
                name: 'Fleet',
                code: 'CX',
                stats: [OrganizationHoloStat('Members', 42)],
              ),
              maxBannerHeight: 160,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1150));
      expect(fractionalOpacityLayers(tester), isNotEmpty);
      light.value = true;
      await tester.pump();
      expect(fractionalOpacityLayers(tester), isEmpty);
      expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
      expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
      expect(find.text('42'), findsOneWidget);
      // Back to the full look: the entrance stays finished. The next frames
      // match the settled header, so nothing replays from half-way.
      light.value = false;
      await tester.pump();
      final restored = fractionalOpacityLayers(tester).length;
      await tester.pumpAndSettle();
      expect(fractionalOpacityLayers(tester).length, restored);
    },
  );
  testWidgets(
    'rail hover settles while a game runs and never returns half-way',
    (tester) async {
      // Hover highlights follow the traditional (mouse) highlight mode.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await pumpLightVisuals(
        tester,
        lightVisualsApp(
          SizedBox(
            height: 96,
            child: OfficialFleetSectionRail(
              items: const [
                OfficialFleetRailItem(
                  section: OfficialFleetWorkspaceSection.members,
                  label: 'Members',
                  summary: 'online',
                ),
              ],
              onSelected: (_) {},
              enterLabel: 'Enter',
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('official-fleet-tab-members'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      List<double> opacities() => tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      // Full look: the hover is really half-way and costs a fractional layer.
      expect(opacities().any((o) => o > 0 && o < 1), isTrue);
      expect(fractionalOpacityLayers(tester), isNotEmpty);
      light.value = true;
      await tester.pump();
      expect(fractionalOpacityLayers(tester), isEmpty);
      // Back to the full look: the highlight stays finished, not half-way.
      light.value = false;
      await tester.pump();
      expect(opacities().any((o) => o > 0 && o < 1), isFalse);
      expect(fractionalOpacityLayers(tester), isEmpty);
      await tester.pumpAndSettle();
    },
  );
}
