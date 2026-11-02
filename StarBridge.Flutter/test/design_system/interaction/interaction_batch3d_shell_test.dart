import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_pane.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;

SuiteSideNavState nav(WidgetTester t) =>
    t.state<SuiteSideNavState>(find.byType(SuiteSideNav));

Future<InMemoryAppPreferences> open(
  WidgetTester t,
  InteractionSuite suite,
) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final prefs = InMemoryAppPreferences(
    initial: AppPreferences.defaults.copyWith(
      interactionStyle: InteractionStyle.values.byName(suite.name),
    ),
  );
  await t.pumpWidget(
    StarBridgeApp(
      composition: AppComposition.forShellReview(
        preferences: prefs,
        windowChrome: InMemoryWindowChrome(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return prefs;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite real shell confirmation stays authoritative', (
      t,
    ) async {
      await open(t, suite);
      await t.tap(find.byKey(const ValueKey('/communities')));
      await t.pumpAndSettle();
      final original = t
          .widget<StarBridgeNavigationPane>(
            find.byType(StarBridgeNavigationPane),
          )
          .selected;
      final indicator = nav(t).indicatorRect;
      final source = t.element(find.byType(StarBridgeShell));
      final navigation = UserInteractionScope.maybeOf(source)!.navigation;
      unawaited(
        navigation.open!(
          source,
          (_) => const Text('Held visitor draft'),
          'navigation.profile',
        ),
      );
      await t.pumpAndSettle();
      final leave = UserPageLeaveScope.maybeOf(
        t.element(find.text('Held visitor draft')),
      )!;
      var answer = Completer<bool>();
      leave.confirm = () => answer.future;
      await t.tap(find.byKey(const ValueKey('/hangar')));
      await t.pump();
      expect(find.text('Held visitor draft'), findsOneWidget);
      expect(
        t
            .widget<StarBridgeNavigationPane>(
              find.byType(StarBridgeNavigationPane),
            )
            .selected,
        original,
      );
      expect(nav(t).indicatorRect, indicator);
      answer.complete(false);
      await t.pumpAndSettle();
      expect(find.text('Held visitor draft'), findsOneWidget);
      answer = Completer<bool>();
      await t.tap(find.byKey(const ValueKey('/hangar')));
      await t.pump();
      answer.complete(true);
      await t.pumpAndSettle();
      expect(find.text('Held visitor draft'), findsNothing);
      expect(
        t
            .widget<StarBridgeNavigationPane>(
              find.byType(StarBridgeNavigationPane),
            )
            .selected
            .route,
        '/hangar',
      );
      expect(nav(t).indicatorRect, nav(t).rectOf('/hangar'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
      '$suite real shell primary keyboard source and live preferences',
      (t) async {
        final prefs = await open(t, suite);
        final row = t.widget<ShellNavigationItem>(
          find.byKey(const ValueKey('/communities')),
        );
        row.focusNode!.requestFocus();
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        final pane = t.widget<StarBridgeNavigationPane>(
          find.byType(StarBridgeNavigationPane),
        );
        expect(pane.selected.route, '/communities');
        expect(pane.interaction, NavigationInteraction.keyboard);
        expect(nav(t).indicatorRect, nav(t).rectOf('/communities'));
        final state = nav(t);
        await prefs.setInteractionStyle(InteractionStyle.glow);
        await prefs.setMotionPreference(MotionPreference.reduce);
        await t.pump();
        await t.pump();
        expect(nav(t), same(state));
        expect(row.focusNode!.hasFocus, true);
        expect(nav(t).indicatorRect, nav(t).rectOf('/communities'));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
