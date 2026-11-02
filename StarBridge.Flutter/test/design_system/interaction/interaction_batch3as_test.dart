import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_route.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_workspace.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3am_test.dart' show action;

FeatureDescriptor feature(String id, Widget content) => FeatureDescriptor(
  id: id,
  route: '/$id',
  labelKey: id,
  descriptionKey: '',
  icon: StarBridgeIconSemantic.profile,
  navigationRegion: NavigationRegion.primary,
  order: 0,
  buildDestination: (_) => content,
);
InteractionSource origin(String value) =>
    value == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;
Future<void> capture(WidgetTester t, GlobalKey key, String name) async =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      final directory = Directory('build/reviews/interaction-batch3as');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'real shell open-self retains final activation source $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              prefs = InMemoryAppPreferences(
                initial: AppPreferences.defaults.copyWith(
                  interactionStyle: InteractionStyle.values.byName(suite.name),
                ),
              ),
              composition = AppComposition.forShellReview(
                windowChrome: InMemoryWindowChrome(),
                preferences: prefs,
              );
          size(t, const Size(1280, 1000));
          await t.pumpWidget(StarBridgeApp(composition: composition));
          await t.pumpAndSettle();
          final context = t.element(find.byType(StarBridgeShell)),
              navigation = UserInteractionScope.maybeOf(context)!.navigation;
          unawaited(
            navigation.open!(
              context,
              (pageContext) => StarBridgeActionButton(
                controlKey: const Key('open-self'),
                onActivate: (source) => unawaited(
                  runStarBridgeActivation<void>(
                    source,
                    () => navigation.openSelf!(pageContext),
                  ),
                ),
                child: const Text('Open self'),
              ),
              'navigation.profile',
            ),
          );
          await t.pumpAndSettle();
          await action(t, const Key('open-self'), source);
          final workspace = t.widget<ShellWorkspace>(
            find.byType(ShellWorkspace),
          );
          expect(workspace.selected.route, '/profile');
          expect(
            workspace.interaction,
            source == 'pointer'
                ? NavigationInteraction.pointer
                : NavigationInteraction.keyboard,
          );
          expect(find.byKey(const Key('open-self')), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
    testWidgets(
      'real user page keeps descendant autofocus and returns by Esc $suite',
      (t) async {
        final prefs = InMemoryAppPreferences(
              initial: AppPreferences.defaults.copyWith(
                interactionStyle: InteractionStyle.values.byName(suite.name),
              ),
            ),
            composition = AppComposition.forShellReview(
              windowChrome: InMemoryWindowChrome(),
              preferences: prefs,
            ),
            focus = FocusNode(),
            controller = TextEditingController();
        addTearDown(focus.dispose);
        addTearDown(controller.dispose);
        size(t, const Size(1280, 1000));
        await t.pumpWidget(StarBridgeApp(composition: composition));
        await t.pumpAndSettle();
        final context = t.element(find.byType(StarBridgeShell)),
            nav = UserInteractionScope.maybeOf(context)!.navigation;
        unawaited(
          nav.open!(
            context,
            (_) => TextField(
              key: const Key('auto-user-editor'),
              autofocus: true,
              focusNode: focus,
              controller: controller,
            ),
            'navigation.profile',
          ),
        );
        await t.pumpAndSettle();
        expect(focus.hasFocus, true);
        await t.enterText(
          find.byKey(const Key('auto-user-editor')),
          'Preserved autofocus',
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('auto-user-editor')), findsNothing);
        expect(controller.text, 'Preserved autofocus');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'root page change follows live reduction without resetting current editor $suite',
      (t) async {
        var destination = feature('a', const Text('A'));
        late StateSetter rebuild;
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final live = await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              rebuild = set;
              return ShellWorkspace(
                selected: destination,
                interaction: NavigationInteraction.pointer,
              );
            },
          ),
          suite,
        );
        rebuild(
          () => destination = feature(
            'b',
            TextField(key: const Key('reduced-editor'), controller: controller),
          ),
        );
        await t.pump();
        await t.enterText(find.byKey(const Key('reduced-editor')), 'Retained');
        final state = t.state<EditableTextState>(find.byType(EditableText));
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        final motion = t.widget<StarBridgePageTransition>(
          find.byType(StarBridgePageTransition),
        );
        expect(motion.animation.value, 1);
        expect(motion.animation.status, AnimationStatus.completed);
        expect(
          t.state<EditableTextState>(find.byType(EditableText)),
          same(state),
        );
        expect(controller.text, 'Retained');
        expect(state.widget.focusNode.hasFocus, true);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'root hides background native viewport under maintained user page $suite',
      (t) async {
        BuildContext? background;
        final nav = GlobalKey<NavigatorState>();
        await mount(
          t,
          Builder(
            builder: (outerContext) => Navigator(
              key: nav,
              onGenerateRoute: (_) => StarBridgePageRoute<void>.fromContext(
                outerContext,
                source: InteractionSource.keyboard,
                builder: (context) => ShellWorkspace(
                  selected: feature(
                    'source',
                    Builder(
                      builder: (context) {
                        background = context;
                        return const Text('Background source');
                      },
                    ),
                  ),
                  interaction: NavigationInteraction.keyboard,
                ),
              ),
            ),
          ),
          suite,
        );
        expect(NativeViewportScope.isActive(background!), true);
        final context = t.element(find.text('Background source'));
        unawaited(
          showStarBridgeDialog<void>(
            context,
            builder: (_) => const AlertDialog(title: Text('Owned popup')),
          ),
        );
        await t.pumpAndSettle();
        expect(NativeViewportScope.isActive(background!), true);
        Navigator.of(t.element(find.text('Owned popup'))).pop();
        await t.pumpAndSettle();
        expect(NativeViewportScope.isActive(background!), true);
        final route = StarBridgePageRoute<void>.fromContext(
          context,
          builder: (_) => const Text('Foreground'),
        );
        unawaited(nav.currentState!.push<void>(route));
        await t.pump();
        await t.pumpAndSettle();
        expect(NativeViewportScope.isActive(background!), false);
        await runStarBridgeActivation<void>(
          InteractionSource.keyboard,
          () => nav.currentState!.pop(),
        );
        await t.pumpAndSettle();
        expect(NativeViewportScope.isActive(background!), true);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'opaque page source entry exit preserves editor and exact result $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              controller = TextEditingController(),
              focus = FocusNode(),
              body = GlobalKey();
          addTearDown(controller.dispose);
          addTearDown(focus.dispose);
          StarBridgePageRoute<int>? page;
          int? result;
          await mount(
            t,
            Builder(
              builder: (context) => StarBridgeActionButton(
                controlKey: const Key('open-page'),
                onActivate: (source) => unawaited(
                  runStarBridgeActivation<void>(source, () async {
                    page = StarBridgePageRoute<int>.fromContext(
                      context,
                      builder: (context) => Material(
                        child: Column(
                          key: body,
                          children: [
                            TextField(
                              key: const Key('page-editor'),
                              controller: controller,
                              focusNode: focus,
                            ),
                            StarBridgeActionButton(
                              controlKey: const Key('close-page'),
                              onActivate: (_) => Navigator.of(context).pop(37),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    );
                    result = await Navigator.of(context).push<int>(page!);
                  }),
                ),
                child: const Text('Open page'),
              ),
            ),
            suite,
          );
          await action(t, const Key('open-page'), source, settle: false);
          expect(page!.opaque, true);
          expect(page!.instant, source != 'pointer');
          expect(page!.animation!.value, source == 'pointer' ? lessThan(1) : 1);
          final initial = t.getRect(find.byKey(body));
          await t.enterText(
            find.byKey(const Key('page-editor')),
            'Retained input',
          );
          final editor = t.state<EditableTextState>(find.byType(EditableText));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 20));
            expect(t.getRect(find.byKey(body)), initial);
          }
          expect(
            t.state<EditableTextState>(find.byType(EditableText)),
            same(editor),
          );
          expect(controller.text, 'Retained input');
          expect(focus.hasFocus, true);
          await action(t, const Key('close-page'), source, settle: false);
          if (source == 'pointer') {
            expect(page!.animation!.value, greaterThan(0));
            expect(
              NativeViewportScope.isActive(
                t.element(find.byKey(const Key('page-editor'))),
              ),
              false,
            );
          } else {
            expect(page!.animation!.value, 0);
          }
          await t.pumpAndSettle();
          expect(result, 37);
          expect(find.byKey(const Key('page-editor')), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
    for (final exit in [false, true]) {
      testWidgets(
        'live reduction settles route controller and unregisters after disposal $suite exit=$exit',
        (t) async {
          StarBridgePageRoute<void>? page;
          final live = await mount(
            t,
            Builder(
              builder: (context) => StarBridgeActionButton(
                controlKey: const Key('open-page'),
                onActivate: (_) {
                  page = StarBridgePageRoute<void>.fromContext(
                    context,
                    builder: (context) => StarBridgeActionButton(
                      controlKey: const Key('close-page'),
                      onActivate: (_) => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  );
                  unawaited(Navigator.of(context).push<void>(page!));
                },
                child: const Text('Open'),
              ),
            ),
            suite,
          );
          await action(t, const Key('open-page'), 'pointer', settle: exit);
          if (exit) {
            await action(t, const Key('close-page'), 'pointer', settle: false);
          }
          live.change(() => live.reduce = true);
          await t.pump();
          await t.pump();
          expect(page!.animation!.value, exit ? 0 : 1);
          expect(
            page!.animation!.status,
            exit ? AnimationStatus.dismissed : AnimationStatus.completed,
          );
          if (!exit) {
            await action(t, const Key('close-page'), 'keyboard');
          }
          await t.pumpAndSettle();
          live.change(() => live.reduce = false);
          await t.pump();
          await t.pump();
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'root page raster stationary, rapid reversal has one global key and active feedback $suite',
      (t) async {
        final fieldKey = GlobalKey(), controller = TextEditingController();
        addTearDown(controller.dispose);
        final a = feature(
              'a',
              TextField(key: fieldKey, controller: controller),
            ),
            b = feature('b', const Text('B page'));
        var selected = a;
        var from = NavigationInteraction.keyboard;
        var calls = 0;
        late StateSetter rebuild;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              rebuild = set;
              return Column(
                children: [
                  StarBridgeActionButton(
                    controlKey: const Key('switch-page'),
                    onActivate: (source) => set(() {
                      calls++;
                      selected = selected == a ? b : a;
                      from = source == InteractionSource.keyboard
                          ? NavigationInteraction.keyboard
                          : NavigationInteraction.pointer;
                    }),
                    child: const Text('Switch'),
                  ),
                  Expanded(
                    child: ShellWorkspace(
                      selected: selected,
                      interaction: from,
                    ),
                  ),
                ],
              );
            },
          ),
          suite,
        );
        await t.enterText(find.byKey(fieldKey), 'Owner draft');
        final editor = t.state<EditableTextState>(find.byType(EditableText));
        rebuild(() => from = NavigationInteraction.pointer);
        await t.pump();
        expect(
          t.state<EditableTextState>(find.byType(EditableText)),
          same(editor),
        );
        for (var i = 0; i < 4; i++) {
          await action(t, const Key('switch-page'), 'pointer', settle: false);
          expect(t.takeException(), isNull);
        }
        expect(calls, 4);
        expect(find.byKey(fieldKey), findsOneWidget);
        final rect = t.getRect(find.byKey(fieldKey));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 20));
          expect(t.getRect(find.byKey(fieldKey)), rect);
        }
        expect(controller.text, 'Owner draft');
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'inactive parent viewport cannot be revived by page paint $suite',
      (t) async {
        final animation = AnimationController(vsync: t, value: 1);
        addTearDown(animation.dispose);
        BuildContext? childContext;
        await mount(
          t,
          NativeViewportScope(
            active: false,
            child: StarBridgePageTransition(
              animation: animation,
              child: Builder(
                builder: (context) {
                  childContext = context;
                  return const Text('Inactive');
                },
              ),
            ),
          ),
          suite,
        );
        expect(NativeViewportScope.isActive(childContext!), false);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final source in [
      'pointer',
      'keyboard',
      'reader',
      'escape',
      'system',
    ]) {
      testWidgets(
        'real shell user stack keeps cancelled guard and returns source state $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              prefs = InMemoryAppPreferences(
                initial: AppPreferences.defaults.copyWith(
                  interactionStyle: InteractionStyle.values.byName(suite.name),
                ),
              ),
              composition = AppComposition.forShellReview(
                windowChrome: InMemoryWindowChrome(),
                preferences: prefs,
              );
          size(t, const Size(1280, 1000));
          await t.pumpWidget(StarBridgeApp(composition: composition));
          await t.pumpAndSettle();
          final context = t.element(find.byType(StarBridgeShell)),
              nav = UserInteractionScope.maybeOf(context)!.navigation;
          unawaited(
            runStarBridgeActivation<void>(
              source == 'escape' || source == 'system'
                  ? InteractionSource.pointer
                  : origin(source),
              () => nav.open!(
                context,
                (_) => const Text('Actual visitor'),
                'navigation.profile',
              ),
            ),
          );
          await t.pumpAndSettle();
          final pageContext = t.element(find.text('Actual visitor')),
              guard = UserPageLeaveScope.maybeOf(pageContext)!,
              route = ModalRoute.of(pageContext)! as StarBridgePageRoute;
          expect(route.instant, source == 'keyboard' || source == 'reader');
          var allow = false;
          var checks = 0;
          InteractionSource? from;
          guard.confirm = () async {
            checks++;
            from = currentStarBridgeActivationSource;
            return allow;
          };
          Future<void> back() async {
            if (source == 'escape') {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pump();
              await t.pumpAndSettle();
            } else if (source == 'system') {
              await Navigator.of(pageContext).maybePop();
              await t.pumpAndSettle();
            } else {
              await action(t, const Key('user-page-back'), source);
            }
          }

          await back();
          expect(checks, 1);
          expect(find.text('Actual visitor'), findsOneWidget);
          expect(
            from,
            source == 'escape'
                ? InteractionSource.keyboard
                : source == 'system'
                ? InteractionSource.pointer
                : origin(source),
          );
          allow = true;
          await back();
          expect(checks, 2);
          expect(find.text('Actual visitor'), findsNothing);
          expect(find.byType(ShellWorkspace), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('render real stationary page entrance $suite', (t) async {
      final key = GlobalKey();
      var selected = feature('a', const Text('Source'));
      late StateSetter rebuild;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, set) {
            rebuild = set;
            return ShellWorkspace(
              selected: selected,
              interaction: NavigationInteraction.pointer,
            );
          },
        ),
        suite,
        capture: key,
      );
      rebuild(
        () => selected = feature(
          'b',
          const ColoredBox(
            color: Color(0xff172831),
            child: Center(child: Text('Destination remains stationary')),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      await capture(t, key, '${suite.name}-enter');
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
  }
}
