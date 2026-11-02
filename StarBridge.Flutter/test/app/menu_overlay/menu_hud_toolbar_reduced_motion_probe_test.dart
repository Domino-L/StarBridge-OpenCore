import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_placement.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_quick_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_surface_app_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_item.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';
import 'package:starbridge_flutter/platform/window/menu_display_preferences.dart';

// Copy this file to test/app/menu_overlay/ in the isolated Flutter runner.
// This is the same viewport helper used by the existing HUD widget tests.
import '../../features/friends/social_layout_test.dart' show size;

const _view = MenuHudQuickView(
  available: true,
  editable: true,
  dirty: false,
  hotkey: 'Ctrl+Shift+O',
  presetName: 'Fixture',
  presets: [],
  modules: {
    'Notice': false,
    'Squads': false,
    'Members': true,
    'Chat': false,
    'Events': false,
    'Crosshair': false,
  },
  placing: true,
  layout: [
    OverlayWorkspaceLayoutItem(
      key: 'Members',
      x: .2,
      y: .45,
      width: .16,
      height: .18,
      horizontalAnchor: 'Left',
      verticalAnchor: 'Top',
      isLocked: false,
      textOpacity: 1,
      backgroundOpacity: .5,
    ),
  ],
);

// Read the opacity applied by the actual render ancestors, rather than the
// AnimatedOpacity target/duration. Also accepts a future static Opacity wrapper.
double _paintOpacity(WidgetTester tester, Finder toolbar) {
  RenderObject? node = tester.renderObject<RenderObject>(toolbar);
  var opacity = 1.0;
  while (node != null) {
    if (node is RenderAnimatedOpacity) {
      opacity *= node.opacity.value;
    } else if (node is RenderOpacity) {
      opacity *= node.opacity;
    }
    node = node.parent;
  }
  return opacity;
}

void main() {
  testWidgets(
    'HUD normal drag keeps fades and live reduce settles both directions',
    (tester) async {
      size(tester, const Size(1920, 1080));
      final observer = NavigatorObserver();
      Widget surface(bool reduced) => MenuSurfaceAppFrame(
        observer: observer,
        interaction: MenuInteractionPresentation(reduceMotion: reduced),
        child: MenuBridgePreview(
          visible: true,
          onDismiss: () {},
          onFeatureVisible: (_, _) {},
          onFeatureAction: (_, _, _) {},
          features: const {
            'hud': MenuFeatureView('ready', hudEnabled: true, hudQuick: _view),
          },
        ),
      );
      await tester.pumpWidget(surface(false));
      await tester.pumpAndSettle();
      final layer = find.byType(MenuHudPlacementLayer);
      final originalState = tester.state(layer);
      final toolbar = find.byKey(const ValueKey('menu-hud-place-toolbar'));
      final module = find.byKey(
        const ValueKey('menu-hud-place-module-Members'),
      );
      // Select first so the existing tools/readout slot stays mounted when
      // dragging starts; a first-ever selection can recreate the toolbar.
      await tester.tap(module);
      await tester.pumpAndSettle();
      final originalToolbarElement = tester.element(toolbar);
      final gesture = await tester.startGesture(tester.getCenter(module));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(64, 32));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _paintOpacity(tester, toolbar),
        allOf(greaterThan(.18), lessThan(1)),
        reason: 'Normal drag must keep perceptible fading, not jump.',
      );

      await tester.pumpWidget(surface(true));
      expect(tester.state(layer), same(originalState));
      expect(tester.element(toolbar), same(originalToolbarElement));
      expect(
        _paintOpacity(tester, toolbar),
        closeTo(.18, .000001),
        reason: 'Enabling reduce during drag must settle on its first frame.',
      );
      await tester.pumpWidget(surface(false));
      await gesture.up();
      await tester.pump();
      expect(_paintOpacity(tester, toolbar), closeTo(.18, .000001));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _paintOpacity(tester, toolbar),
        allOf(greaterThan(.18), lessThan(1)),
        reason: 'Normal release must retain its existing fade.',
      );

      await tester.pumpWidget(surface(true));
      expect(tester.state(layer), same(originalState));
      expect(tester.element(toolbar), same(originalToolbarElement));
      expect(
        _paintOpacity(tester, toolbar),
        closeTo(1, .000001),
        reason:
            'Enabling reduce during release must restore paint immediately.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final source in ['outer', 'local', 'safe']) {
    testWidgets(
      'HUD $source reduce reaches drag and release paint endpoints on first frame',
      (tester) async {
        size(tester, const Size(1920, 1080));
        final actions = <({String tool, String key, String value})>[];
        var dismissed = 0;
        final tools = source == 'local'
            ? (MenuLocalToolsController((_, _) async => null)
                ..display = const MenuDisplayPreferences(reduceMotion: true))
            : null;
        if (tools != null) addTearDown(tools.dispose);
        await tester.pumpWidget(
          MenuSurfaceAppFrame(
            observer: NavigatorObserver(),
            interaction: MenuInteractionPresentation(
              reduceMotion: source == 'outer',
            ),
            child: MenuBridgePreview(
              visible: true,
              startupMode: source == 'safe' ? 'safe' : 'normal',
              localToolsController: tools,
              onDismiss: () => dismissed++,
              onFeatureVisible: (_, _) {},
              onFeatureAction: (tool, key, value) =>
                  actions.add((tool: tool, key: key, value: value)),
              features: const {
                'hud': MenuFeatureView(
                  'ready',
                  hudEnabled: true,
                  hudQuick: _view,
                ),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final layer = find.byType(MenuHudPlacementLayer);
        expect(layer, findsOneWidget);
        expect(
          resolveStarBridgeInteraction(tester.element(layer)).reduceMotion,
          isTrue,
          reason:
              'Reduced motion must arrive through the real placement entry.',
        );
        final toolbar = find.byKey(const ValueKey('menu-hud-place-toolbar'));
        final module = find.byKey(
          const ValueKey('menu-hud-place-module-Members'),
        );
        final readout = find.byKey(const ValueKey('menu-hud-place-readout'));
        final toolbarRect = tester.getRect(toolbar);
        final initialModuleRect = tester.getRect(module);
        expect(_paintOpacity(tester, toolbar), 1);

        // Keep the original pan recognizer active across sampled frames. The
        // first move admits the pan; the second must update real local geometry.
        final gesture = await tester.startGesture(tester.getCenter(module));
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump();
        final dragFirstPaint = _paintOpacity(tester, toolbar);
        await gesture.moveBy(const Offset(64, 32));
        await tester.pump();
        expect(
          tester.getRect(module).topLeft,
          isNot(initialModuleRect.topLeft),
        );
        expect(readout, findsOneWidget);
        expect(tester.getRect(toolbar), toolbarRect);
        expect(actions, isNotEmpty);
        expect(
          actions.every(
            (action) => action.tool == 'hud' && action.key == 'placeItem',
          ),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 16));
        final dragNextPaint = _paintOpacity(tester, toolbar);

        // Establish the old settled drag state before testing the independent
        // release transition. Endpoint assertions are deferred so both directions
        // are exercised even if the initial fade violates the reduce contract.
        await tester.pump(const Duration(milliseconds: 200));
        final dragSettledPaint = _paintOpacity(tester, toolbar);
        await gesture.up();
        await tester.pump();
        final releaseFirstPaint = _paintOpacity(tester, toolbar);
        expect(readout, findsNothing);
        expect(
          find.byKey(const ValueKey('menu-hud-place-module-tools')),
          findsOneWidget,
        );
        expect(tester.getRect(toolbar), toolbarRect);
        await tester.pump(const Duration(milliseconds: 16));
        final releaseNextPaint = _paintOpacity(tester, toolbar);

        // Verify resumed hit testing through an existing toolbar command. This
        // callback only records an intent; no session/port/persistence is present.
        await tester.tap(find.byKey(const ValueKey('menu-hud-place-done')));
        await tester.pump();
        expect(actions.last, (tool: 'hud', key: 'placeDone', value: ''));
        expect(dismissed, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());

        expect(dragSettledPaint, closeTo(.18, .000001));
        expect(
          [dragFirstPaint, dragNextPaint],
          everyElement(closeTo(.18, .000001)),
          reason:
              'Reduce keeps drag dimming feedback but reaches .18 immediately.',
        );
        expect(
          [releaseFirstPaint, releaseNextPaint],
          everyElement(closeTo(1, .000001)),
          reason:
              'Reduce restores the actual toolbar paint opacity immediately.',
        );
      },
    );
  }
}
