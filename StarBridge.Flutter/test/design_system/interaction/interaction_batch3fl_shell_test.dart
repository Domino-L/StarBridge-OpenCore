import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/app/shell/widgets/brand_home_button.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_top_bar.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;

/// Actual App and original shell/leave machinery. Primary navigation/back
/// use actual inputs. Visitor opening uses the public navigation API with an
/// explicit command origin, not an avatar-menu UI acceptance claim.
class ShellProbe {
  ShellProbe(this.suite) {
    composition = AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
      preferences: InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(
          interactionStyle: InteractionStyle.values.byName(suite.name),
        ),
      ),
    );
  }
  final InteractionSuite suite;
  late final AppComposition composition;
  late UserPageNavigation navigation;
  final root = GlobalKey<NavigatorState>();
  late BuildContext source;
  final draft = TextEditingController();
  Completer<bool>? pendingLeave;
  int leaveCalls = 0;

  Widget app() => StarBridgeApp(composition: composition, navigatorKey: root);

  void attachSource(BuildContext source) {
    this.source = source;
    navigation = UserInteractionScope.maybeOf(source)!.navigation;
  }

  void open(String input) => unawaited(
    runStarBridgeActivation<void>(
      input == 'pointer'
          ? InteractionSource.pointer
          : InteractionSource.keyboard,
      () => navigation.open!(
        source,
        (_) => Builder(
          builder: (context) {
            UserPageLeaveScope.maybeOf(context)!.confirm = () {
              leaveCalls++;
              return pendingLeave?.future ?? Future.value(true);
            };
            return TextField(
              key: const Key('3fl-visitor-draft'),
              controller: draft,
            );
          },
        ),
        'navigation.profile',
      ),
    ),
  );
}

Future<void> openVisitor(WidgetTester t, ShellProbe p, String source) async {
  p.open(source);
  await t.pump();
  await t.pump();
}

Future<void> frames(WidgetTester t, [int count = 8]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Finder navTarget(String target) => target == 'home'
    ? find.descendant(
        of: find.byType(BrandHomeButton),
        matching: find.byType(SuitePressable),
      )
    : find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ShellNavigationItem && w.descriptor.route == '/tools',
        ),
        matching: find.byType(SuitePressable),
      );

Future<void> input(WidgetTester t, Finder target, String source) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'reader') {
    final widget = t.widget(target);
    final texts = find.descendant(of: target, matching: find.byType(Text));
    final label =
        (widget is SuitePressable ? widget.semanticLabel : null) ??
        (texts.evaluate().isEmpty
            ? t.getSemantics(target).label
            : t.widget<Text>(texts.first).data!);
    final candidates = exposedNodes(t)
        .where(
          (n) =>
              n.getSemanticsData().label == label &&
              n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        )
        .toList();
    expect(
      candidates,
      hasLength(1),
      reason: 'Exactly one exposed action for $label',
    );
    final node = candidates.single;
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    final control = t.widget(target);
    final node = switch (control) {
      SuitePressable p => p.focusNode!,
      ButtonStyleButton p => p.focusNode!,
      IconButton p => p.focusNode!,
      _ => throw StateError('Not an actual focusable target: $control'),
    };
    for (var i = 0; i < 100 && !node.hasPrimaryFocus; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(node.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await t.pump();
  await t.pump();
}

ShellTopBar header(WidgetTester t) =>
    t.widget<ShellTopBar>(find.byType(ShellTopBar));
double titleProgress(WidgetTester t) => t
    .widget<StarBridgePageTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('shell-title-switcher')),
        matching: find.byType(StarBridgePageTransition),
      ),
    )
    .animation
    .value;

void assertSource(WidgetTester t, String source) {
  expect(
    header(t).interaction,
    source == 'pointer'
        ? NavigationInteraction.pointer
        : NavigationInteraction.keyboard,
  );
  expect(titleProgress(t), source == 'pointer' ? lessThan(1) : 1);
}

Finder backTarget(WidgetTester t) {
  final owner = find.byKey(const Key('user-page-back'));
  expect(owner, findsOneWidget);
  final widget = t.widget(owner);
  if (widget is SuitePressable || widget is IconButton) return owner;
  return find.descendant(of: owner, matching: find.byType(SuitePressable));
}

Future<void> mount(WidgetTester t, ShellProbe p) async {
  size(t, const Size(1440, 900));
  await t.pumpWidget(p.app());
  await frames(t);
  p.attachSource(t.element(find.byType(StarBridgeShell)));
  await frames(t, 2);
  expect(header(t).selected, same(p.composition.features.home));
  expect(titleProgress(t), 1);
}

Future<void> close(WidgetTester t, ShellProbe p) async {
  await t.pumpWidget(const SizedBox());
  p.draft.dispose();
  await frames(t, 2);
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite actual shell main navigation title $source', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final p = ShellProbe(suite);
        try {
          await mount(t, p);
          await input(t, navTarget('tools'), source);
          expect(header(t).selected.route, '/tools');
          assertSource(t, source);
          await frames(t);
          expect(titleProgress(t), 1);
          await input(t, navTarget('home'), source);
          expect(header(t).selected, same(p.composition.features.home));
          assertSource(t, source);
          await close(t, p);
        } finally {
          semantics.dispose();
        }
      });

      testWidgets(
        '$suite visitor API origin and actual back keeps denied draft and final $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = ShellProbe(suite);
          try {
            await mount(t, p);
            await openVisitor(t, p, source);
            expect(header(t).selected.route, '/profile');
            assertSource(t, source);
            await frames(t);
            await t.enterText(
              find.byKey(const Key('3fl-visitor-draft')),
              'keep this unsaved draft',
            );
            await t.pump();
            p.pendingLeave = Completer<bool>();
            await input(t, backTarget(t), source);
            expect(p.leaveCalls, 1);
            expect(header(t).selected.route, '/profile');
            expect(titleProgress(t), 1);
            p.pendingLeave!.complete(false);
            await frames(t);
            expect(p.draft.text, 'keep this unsaved draft');
            expect(header(t).selected.route, '/profile');
            p.pendingLeave = Completer<bool>();
            await input(t, backTarget(t), source);
            expect(p.leaveCalls, 2);
            p.pendingLeave!.complete(true);
            await t.pump();
            await t.pump();
            expect(header(t).selected, same(p.composition.features.home));
            assertSource(t, source);
            await close(t, p);
          } finally {
            semantics.dispose();
          }
        },
      );

      for (final target in ['home', 'tools']) {
        testWidgets(
          '$suite primary $target while visitor pending keeps newer title source $source',
          (t) async {
            final semantics = t.ensureSemantics();
            final p = ShellProbe(suite);
            try {
              await mount(t, p);
              await openVisitor(t, p, 'pointer');
              await frames(t);
              p.pendingLeave = Completer<bool>();
              await input(t, navTarget(target), source);
              expect(p.leaveCalls, 1);
              expect(header(t).selected.route, '/profile');
              p.pendingLeave!.complete(false);
              await frames(t);
              expect(header(t).selected.route, '/profile');
              p.pendingLeave = Completer<bool>();
              await input(t, navTarget(target), source);
              expect(p.leaveCalls, 2);
              p.pendingLeave!.complete(true);
              await t.pump();
              await t.pump();
              expect(
                header(t).selected.route,
                target == 'tools'
                    ? '/tools'
                    : p.composition.features.home.route,
              );
              assertSource(t, source);
              await frames(t);
              expect(
                header(t).interaction,
                source == 'pointer'
                    ? NavigationInteraction.pointer
                    : NavigationInteraction.keyboard,
              );
              expect(titleProgress(t), 1);
              await close(t, p);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '$suite late leave after shell unmount has no title or navigator resurrection',
      (t) async {
        final p = ShellProbe(suite);
        await mount(t, p);
        await openVisitor(t, p, 'pointer');
        await frames(t);
        p.pendingLeave = Completer<bool>();
        await input(t, navTarget('tools'), 'pointer');
        expect(p.leaveCalls, 1);
        await t.pumpWidget(const SizedBox());
        p.pendingLeave!.complete(true);
        await frames(t);
        expect(find.byType(StarBridgeShell), findsNothing);
        expect(find.byType(ShellTopBar), findsNothing);
        expect(p.navigation.open, isNull);
        p.draft.dispose();
        expect(t.takeException(), isNull);
      },
    );
  }
}
