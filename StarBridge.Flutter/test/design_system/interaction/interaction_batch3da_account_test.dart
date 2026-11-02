import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_menu.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3by_test.dart' show MenuFixture;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3cz_presence_test.dart' show menuSurface;
import 'interaction_batch3i_test.dart' show scopedApp;

FeatureDescriptor destination(String id) => FeatureDescriptor(
  id: id,
  route: '/$id',
  labelKey: 'top.account',
  descriptionKey: 'top.account',
  icon: MenuFixture.descriptor.icon,
  navigationRegion: NavigationRegion.accountMenu,
  order: 1,
  availability: FeatureAvailability.comingSoon,
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      testWidgets(
        '$suite light=$light actual account menu dynamic rows and nested reduced feedback',
        (t) async {
          final h = MenuFixture()..pending = Completer<void>();
          final stage = ValueNotifier(0);
          final boundary = GlobalKey();
          final a = destination('a'),
              b = destination('b'),
              c = destination('c');
          try {
            await t.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: ValueListenableBuilder<int>(
                  valueListenable: stage,
                  builder: (context, value, _) => scopedApp(
                    AccountMenu(
                      destinations: switch (value) {
                        0 => [a, b, c],
                        1 => [c, a],
                        _ => [c, a, b],
                      },
                      projection: h.projection,
                      expanded: true,
                      manualPresence: h.controller,
                      onSelect: (d) => h.actions.add((
                        d.id,
                        currentStarBridgeActivationSource,
                      )),
                      onLogin: () => h.actions.add((
                        'login',
                        currentStarBridgeActivationSource,
                      )),
                      onLogout: () => h.actions.add((
                        'logout',
                        currentStarBridgeActivationSource,
                      )),
                      onIssueAction: () => h.actions.add((
                        'issue',
                        currentStarBridgeActivationSource,
                      )),
                    ),
                    suite,
                    light: light,
                    reduce: value == 2,
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            await fire(t, 'keyboard', 'account-identity-command');
            await t.pumpAndSettle();
            expect(nativeViewportMenus.value, 1);
            final press = await t.startGesture(
              t.getCenter(find.byKey(const Key('account-menu-b'))),
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 30));
            stage.value = 1;
            await t.pump();
            await t.pump();
            expect(find.byKey(const Key('account-menu-b')), findsNothing);
            stage.value = 2;
            await t.pump();
            await t.pump();
            await press.up();
            await t.pump();
            await t.pump();
            expect(
              h.actions,
              isEmpty,
              reason:
                  'Removed press cannot target a restored or reordered command',
            );
            expect(h.writes, isEmpty);
            expect(find.byKey(const Key('account-menu-b')), findsOneWidget);
            await fire(t, 'keyboard', 'account-presence-menu');
            await t.pump();
            await t.pump();
            expect(menuSurface(), findsNWidgets(2));
            final before = await pixels(t, boundary);
            await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await t.pump();
            await t.pump();
            final changed = await pixels(t, boundary);
            expect(changed, isNot(orderedEquals(before)));
            await t.pump(const Duration(milliseconds: 80));
            expect(await pixels(t, boundary), orderedEquals(changed));
            expect(h.actions, isEmpty);
            expect(h.writes, isEmpty);
            await fire(t, 'keyboard', 'manual-presence-invisible');
            await t.pump();
            await t.pump();
            expect(h.writes, hasLength(1));
            expect(h.controller.busy, isTrue);
            expect(menuSurface(), findsNWidgets(2));
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
            expect(menuSurface(), findsNothing);
            expect(nativeViewportMenus.value, 0);
            expect(h.actions, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
            stage.dispose();
          }
        },
      );
    }
  }
}
