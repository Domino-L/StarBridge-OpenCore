import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, PointerDeviceKind, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_pane.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app, pixels;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts;

class NavHarness extends StatefulWidget {
  const NavHarness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<NavHarness> createState() => NavHarnessState();
}

class NavHarnessState extends State<NavHarness> {
  final count = ValueNotifier(0), primary = ValueNotifier(true);
  final boundary = GlobalKey();
  late var suite = widget.suite;
  var reduce = false, light = false;
  var textScale = 1.0;
  var mode = ShellLayoutMode.wide;
  var landings = 0, reads = 0;
  Completer<bool>? guard;
  final requests = <(String, NavigationInteraction)>[];
  late final home = descriptor(
    'home',
    '/',
    NavigationRegion.brand,
    0,
    'navigation.home',
    StarBridgeIconSemantic.community,
  );
  late final rooms = descriptor(
    'rooms',
    '/rooms',
    NavigationRegion.primary,
    0,
    'navigation.rooms',
    StarBridgeIconSemantic.room,
    attention: count,
  );
  late final communities = descriptor(
    'communities',
    '/communities',
    NavigationRegion.primary,
    1,
    'navigation.communities',
    StarBridgeIconSemantic.community,
    primary: primary,
    landing: () async {
      landings++;
      primary.value = true;
    },
    panel: (_, _, _, activate) => TextButton(
      key: const Key('nested-native'),
      onPressed: () async {
        if (await activate()) primary.value = false;
      },
      child: const Text('Nested organization (owner)'),
    ),
  );
  late final hangar = descriptor(
    'hangar',
    '/hangar',
    NavigationRegion.personal,
    0,
    'navigation.hangar',
    StarBridgeIconSemantic.hangar,
  );
  late final settings = descriptor(
    'settings',
    '/settings',
    NavigationRegion.personal,
    1,
    'navigation.settings',
    StarBridgeIconSemantic.settings,
  );
  late final extras = [
    for (var i = 0; i < 18; i++)
      descriptor(
        'extra$i',
        '/extra$i',
        NavigationRegion.primary,
        i + 2,
        'navigation.tools',
        StarBridgeIconSemantic.tools,
      ),
  ];
  late final registry = FeatureRegistry([
    home,
    rooms,
    communities,
    ...extras,
    hangar,
    settings,
  ]);
  late FeatureDescriptor selected = rooms;
  var source = NavigationInteraction.keyboard;

  FeatureDescriptor descriptor(
    String id,
    String route,
    NavigationRegion region,
    int order,
    String label,
    StarBridgeIconSemantic icon, {
    ValueNotifier<int>? attention,
    ValueNotifier<bool>? primary,
    Future<void> Function()? landing,
    NavigationPanelBuilder? panel,
  }) => FeatureDescriptor(
    id: id,
    route: route,
    labelKey: label,
    descriptionKey: label,
    icon: icon,
    navigationRegion: region,
    order: order,
    attentionCount: attention,
    primaryNavigationSelected: primary,
    onPrimaryNavigation: landing,
    buildNavigationPanel: panel,
    prefetch: () async {
      reads++;
    },
    buildDestination: (_) => const SizedBox(),
  );

  Future<bool> requestNavigation(
    FeatureDescriptor d,
    NavigationInteraction interaction,
  ) async {
    requests.add((d.route, interaction));
    final allow = guard == null || await guard!.future;
    if (!mounted || !allow) return false;
    setState(() {
      selected = d;
      source = interaction;
    });
    return true;
  }

  void change(VoidCallback fn) => setState(fn);
  @override
  void dispose() {
    count.dispose();
    primary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => app(
    RepaintBoundary(
      key: boundary,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SizedBox(
          height: 570,
          child: Row(
            children: [
              StarBridgeNavigationPane(
                registry: registry,
                selected: selected,
                mode: mode,
                interaction: source,
                onSelect: (d, s) => unawaited(requestNavigation(d, s)),
                onActivateWithSource: requestNavigation,
              ),
              const Expanded(
                child: Center(child: Text('Client-owned workspace')),
              ),
            ],
          ),
        ),
      ),
    ),
    suite: suite,
    reduce: reduce,
    light: light,
  );
}

Future<NavHarnessState> mount(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<NavHarnessState>();
  await t.pumpWidget(NavHarness(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

SuiteSideNavState motion(WidgetTester t) =>
    t.state<SuiteSideNavState>(find.byType(SuiteSideNav));
Future<void> steps(WidgetTester t, int milliseconds) async {
  for (var n = 0; n < milliseconds; n += 20) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3D'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3d');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite rejected and pending navigation never moves selection',
      (t) async {
        final h = await mount(t, suite);
        final initial = motion(t).indicatorRect;
        h.guard = Completer<bool>();
        await t.tap(find.byKey(const ValueKey('/communities')));
        await t.pump();
        await steps(t, 300);
        expect(h.selected, h.rooms);
        expect(h.landings, 0);
        expect(motion(t).indicatorRect, initial);
        h.guard!.complete(false);
        await t.pumpAndSettle();
        expect(h.selected, h.rooms);
        expect(h.landings, 0);
        h.guard = Completer<bool>();
        await t.tap(find.byKey(const ValueKey('/communities')));
        await t.pump();
        expect(h.landings, 0);
        h.guard!.complete(true);
        await t.pumpAndSettle();
        expect(h.landings, 1);
        expect(h.selected, h.communities);
        expect(motion(t).indicatorRect, motion(t).rectOf('/communities'));
        expect(
          h.requests.map((r) => r.$2),
          everyElement(NavigationInteraction.pointer),
        );
      },
    );

    testWidgets('$suite reader and keyboard landing preserve instant source', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      try {
        final h = await mount(t, suite);
        final item = t.widget<ShellNavigationItem>(
          find.byKey(const ValueKey('/communities')),
        );
        item.focusNode!.requestFocus();
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
        await t.pump();
        await t.pump();
        expect(h.landings, 1);
        expect(h.requests.last.$2, NavigationInteraction.keyboard);
        expect(motion(t).indicatorRect, motion(t).rectOf('/communities'));
        final nodes = exposedNodes(t)
            .where((n) => n.getSemanticsData().label == 'My Hangar')
            .toList();
        expect(nodes, hasLength(1));
        t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          nodes.single.id,
          SemanticsAction.tap,
        );
        await t.pump();
        await t.pump();
        expect(h.requests.last, ('/hangar', NavigationInteraction.keyboard));
        expect(motion(t).indicatorRect, motion(t).rectOf('/hangar'));
        expect(
          testerFocus(t, '/communities'),
          isTrue,
          reason: 'Reader activation does not steal keyboard focus',
        );
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      '$suite primary-personal-home and rapid reversal have one target',
      (t) async {
        final h = await mount(t, suite);
        await t.tap(find.byKey(const ValueKey('/hangar')));
        await t.pump();
        await steps(t, 80);
        await t.tap(find.byKey(const ValueKey('/communities')));
        await t.pump();
        await steps(t, 40);
        await t.tap(find.byKey(const ValueKey('/settings')));
        await t.pumpAndSettle();
        expect(h.requests.length, 3);
        expect(h.selected, h.settings);
        expect(motion(t).indicatorRect, motion(t).rectOf('/settings'));
        h.change(() {
          h.selected = h.home;
          h.source = NavigationInteraction.pointer;
        });
        await t.pumpAndSettle();
        expect(motion(t).indicatorRect, isNull);
        h.change(() {
          h.selected = h.rooms;
        });
        await t.pumpAndSettle();
        expect(motion(t).indicatorRect, motion(t).rectOf('/rooms'));
        expect(find.byType(SuiteSideNav), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite pointer feedback survives repeated same-destination clicks',
      (t) async {
        final h = await mount(t, suite);
        final before = await pixels(t, h.boundary);
        for (var i = 0; i < 4; i++) {
          await t.tap(find.byKey(const ValueKey('/rooms')));
          await t.pump();
          await steps(t, 60);
          expect(await pixels(t, h.boundary), isNot(before));
        }
        expect(h.requests.length, 4);
        expect(h.selected, h.rooms);
        expect(motion(t).indicatorRect, motion(t).rectOf('/rooms'));
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      '$suite scroll resize badges do not replay selection or replace glyphs',
      (t) async {
        final h = await mount(t, suite);
        final nav = motion(t);
        final item = t.widget<ShellNavigationItem>(
          find.byKey(const ValueKey('/rooms')),
        );
        final focus = item.focusNode;
        final before = nav.indicatorRect!;
        nav.scrollController.jumpTo(20);
        await t.pump();
        await t.pump();
        expect(nav.indicatorRect!.top, closeTo(before.top - 20, .01));
        expect(nav.indicatorRect, nav.rectOf('/rooms'));
        nav.scrollController.jumpTo(0);
        await t.pumpAndSettle();
        h.count.value = 100;
        await t.pumpAndSettle();
        for (final mode in ShellLayoutMode.values) {
          h.change(() {
            h.mode = mode;
          });
          await t.pumpAndSettle();
          expect(motion(t), same(nav));
          final current = t.widget<ShellNavigationItem>(
            find.byKey(const ValueKey('/rooms')),
          );
          expect(current.focusNode, same(focus));
          expect(nav.indicatorRect, nav.rectOf('/rooms'));
          final icon = find.descendant(
            of: find.byKey(const ValueKey('/rooms')),
            matching: find.byType(StarBridgeIcon),
          );
          expect(t.widget<StarBridgeIcon>(icon).semantic, h.rooms.icon);
          final tokens = t
              .element(find.byType(StarBridgeNavigationPane))
              .tokens;
          expect(
            t.getSize(find.byType(StarBridgeNavigationPane)).width,
            switch (mode) {
              ShellLayoutMode.wide => tokens.density.navigationWide,
              ShellLayoutMode.compact => tokens.density.navigationCompact,
              ShellLayoutMode.iconOnly => tokens.density.navigationIconOnly,
            },
          );
          expect(
            t.getSize(find.byKey(const ValueKey('/rooms'))).height,
            tokens.density.navigationItemHeight,
          );
        }
        expect(h.requests, isEmpty);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite nested owner hides primary marker without losing native panel',
      (t) async {
        final h = await mount(t, suite);
        h.change(() {
          h.selected = h.communities;
        });
        await t.pumpAndSettle();
        expect(motion(t).indicatorRect, isNotNull);
        h.primary.value = false;
        await t.pumpAndSettle();
        expect(motion(t).indicatorRect, isNull);
        expect(
          t
              .widget<ShellNavigationItem>(
                find.byKey(const ValueKey('/communities')),
              )
              .selected,
          false,
        );
        motion(t).scrollController
            .jumpTo(motion(t).scrollController.position.maxScrollExtent);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('nested-native')), findsOneWidget);
        motion(t).scrollController.jumpTo(0);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('/communities')));
        await t.pumpAndSettle();
        expect(h.primary.value, isTrue);
        expect(h.landings, 1);
        expect(motion(t).indicatorRect, motion(t).rectOf('/communities'));
      },
    );

    testWidgets(
      '$suite live style reduce and keyboard interruption finish marker',
      (t) async {
        final h = await mount(t, suite);
        final nav = motion(t);
        final focus = t
            .widget<ShellNavigationItem>(find.byKey(const ValueKey('/rooms')))
            .focusNode!;
        focus.requestFocus();
        await t.pumpAndSettle();
        h.change(() {
          h.selected = h.hangar;
          h.source = NavigationInteraction.pointer;
        });
        await t.pump();
        await steps(t, 40);
        h.change(() {
          h.reduce = true;
          h.light = true;
        });
        await t.pump();
        await t.pump();
        expect(nav.indicatorRect, nav.rectOf('/hangar'));
        expect(focus.hasFocus, true);
        h.change(() {
          h.reduce = false;
          h.suite = InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(motion(t), same(nav));
        expect(focus.hasFocus, true);
        h.change(() {
          h.selected = h.settings;
          h.source = NavigationInteraction.pointer;
        });
        await t.pump();
        await steps(t, 30);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        expect(h.requests.last.$2, NavigationInteraction.keyboard);
        expect(nav.indicatorRect, nav.rectOf('/rooms'));
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(t.takeException(), isNull);
        expect(t.binding.hasScheduledFrame, false);
      },
    );

    testWidgets(
      '$suite arrows focus actual destinations rather than nested controls',
      (t) async {
        final h = await mount(t, suite);
        final row = t.widget<ShellNavigationItem>(
          find.byKey(const ValueKey('/rooms')),
        );
        row.focusNode!.requestFocus();
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        await t.pump();
        expect(h.selected, h.communities);
        expect(testerFocus(t, '/communities'), true);
        expect(h.landings, 1);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        await t.pump();
        expect(h.selected, h.extras.first);
        expect(testerFocus(t, '/extra0'), true);
        expect(
          h.requests.map((r) => r.$2),
          everyElement(NavigationInteraction.keyboard),
        );
        expect(motion(t).indicatorRect, motion(t).rectOf('/extra0'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('$suite breakpoint preserves nonzero scroll and focus', (
      t,
    ) async {
      final h = await mount(t, suite);
      final nav = motion(t);
      final focus = t
          .widget<ShellNavigationItem>(
            find.byKey(const ValueKey('/communities')),
          )
          .focusNode!;
      focus.requestFocus();
      await t.pumpAndSettle();
      nav.scrollController.jumpTo(20);
      await t.pumpAndSettle();
      h.change(() {
        h.mode = ShellLayoutMode.iconOnly;
      });
      await t.pumpAndSettle();
      expect(motion(t), same(nav));
      expect(nav.scrollController.offset, 20);
      expect(focus.hasFocus, true);
      h.change(() {
        h.mode = ShellLayoutMode.wide;
      });
      await t.pumpAndSettle();
      expect(nav.scrollController.offset, 20);
      expect(focus.hasFocus, true);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      '$suite actual row hover prefetch remains bounded and readonly',
      (t) async {
        final h = await mount(t, suite);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('/rooms'))));
        await t.pump(const Duration(milliseconds: 200));
        await mouse.moveTo(const Offset(700, 500));
        await t.pump(const Duration(milliseconds: 400));
        expect(h.reads, 0);
        await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('/rooms'))));
        await t.pump(const Duration(milliseconds: 350));
        expect(h.reads, 1);
        h.count.value = 42;
        await t.pump();
        await steps(t, 500);
        expect(h.reads, 1);
        expect(h.requests, isEmpty);
        expect(h.selected, h.rooms);
        await mouse.removePointer();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('$suite light two-times text retains navigation geometry', (
      t,
    ) async {
      final h = await mount(t, suite);
      h.change(() {
        h.light = true;
        h.textScale = 2;
      });
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('/hangar')));
      await t.pumpAndSettle();
      expect(motion(t).indicatorRect, motion(t).rectOf('/hangar'));
      expect(t.takeException(), isNull);
    });

    testWidgets('$suite real navigation layout review frames', (t) async {
      final h = await mount(t, suite);
      await capture(t, h.boundary, '${suite.name}-idle');
      await t.tap(find.byKey(const ValueKey('/hangar')));
      await t.pump();
      await steps(t, 100);
      await capture(t, h.boundary, '${suite.name}-cross-region');
      await t.pumpAndSettle();
      h.change(() {
        h.mode = ShellLayoutMode.iconOnly;
      });
      await t.pumpAndSettle();
      await capture(t, h.boundary, '${suite.name}-icon-only');
      expect(t.takeException(), isNull);
    });
  }
}

bool testerFocus(WidgetTester t, String route) => t
    .widget<ShellNavigationItem>(find.byKey(ValueKey(route)))
    .focusNode!
    .hasFocus;
