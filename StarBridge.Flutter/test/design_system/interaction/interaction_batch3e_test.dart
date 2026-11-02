import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_workspace.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_group_navigation.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';
import 'package:starbridge_flutter/platform/window/menu_desktop_widgets.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app, pixels;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/menu_settings_workspace_test.dart'
    show Port;
import '../../features/overlay_settings/overlay_appearance_preview_page_test.dart'
    show Workspace;

class Harness extends StatefulWidget {
  const Harness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  var selected = 'notice', reduce = false, light = false, accept = true;
  var groups = ['notice', 'members', 'chat', 'events'];
  final calls = <String>[];
  final boundary = GlobalKey();
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => app(
    RepaintBoundary(
      key: boundary,
      child: SizedBox(
        width: 240,
        height: 320,
        child: OverlayWorkspaceGroupNavigation(
          selected: selected,
          groups: groups,
          title: 'Workspace',
          label: (id) => id,
          icon: (_) => StarBridgeIconSemantic.tools,
          onSelected: (id) {
            calls.add(id);
            if (accept) setState(() => selected = id);
          },
        ),
      ),
    ),
    suite: suite,
    reduce: reduce,
    light: light,
  );
}

Widget workspaceApp(Widget child, InteractionSuite suite) {
  final base =
      app(child, suite: suite, locale: const Locale('zh', 'CN')) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    themeAnimationDuration: Duration.zero,
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark),
      const Locale('zh', 'CN'),
      interactionSuite: suite,
    ),
    home: Scaffold(body: child),
  );
}

Finder row(String id, [String prefix = 'overlay-group']) =>
    find.byKey(Key('$prefix-nav-$id'));
SuiteSideNavState motion(WidgetTester t) =>
    t.state<SuiteSideNavState>(find.byType(SuiteSideNav));
FocusNode focus(WidgetTester t, String id) {
  final widget = t.widget(row(id));
  return widget is SuitePressable
      ? widget.focusNode!
      : (widget as InkWell).focusNode!;
}

Future<HarnessState> mount(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3E'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final folder = Directory('build/reviews/interaction-batch3e');
      await folder.create(recursive: true);
      await File('${folder.path}/$name.png')
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
      '$suite selection follows owner, repeated presses still dispatch',
      (t) async {
        final h = await mount(t, suite);
        h.accept = false;
        await t.tap(row('members'));
        await t.pumpAndSettle();
        expect(h.selected, 'notice');
        expect(motion(t).indicatorRect, motion(t).rectOf('notice'));
        h.accept = true;
        for (final id in ['members', 'chat', 'members', 'members']) {
          await t.tap(row(id));
          await t.pump(const Duration(milliseconds: 20));
        }
        await t.pumpAndSettle();
        expect(h.calls, ['members', 'members', 'chat', 'members', 'members']);
        expect(h.selected, 'members');
        expect(motion(t).indicatorRect, motion(t).rectOf('members'));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('$suite current item retains pointer feedback', (t) async {
      final h = await mount(t, suite);
      final idle = await pixels(t, h.boundary);
      await t.tap(row('notice'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(await pixels(t, h.boundary), isNot(idle));
      expect(h.calls, ['notice']);
      await t.pumpAndSettle();
    });

    testWidgets(
      '$suite arrows, enter and reader activate immediately with one label',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final h = await mount(t, suite);
          focus(t, 'notice').requestFocus();
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await t.pump();
          await t.pump();
          expect(h.selected, 'members');
          expect(focus(t, 'members').hasFocus, isTrue);
          expect(motion(t).indicatorRect, motion(t).rectOf('members'));
          await t.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
          await t.pump();
          expect(h.calls, ['members', 'members']);
          final nodes = exposedNodes(t)
              .where((n) => n.getSemanticsData().label == 'chat')
              .toList();
          expect(nodes, hasLength(1));
          t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
            nodes.single.id,
            SemanticsAction.tap,
          );
          await t.pump();
          await t.pump();
          expect(h.selected, 'chat');
          expect(motion(t).indicatorRect, motion(t).rectOf('chat'));
          expect(focus(t, 'members').hasFocus, isTrue);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('$suite live reduce and style settle without replacing focus', (
      t,
    ) async {
      final h = await mount(t, suite);
      final node = focus(t, 'notice');
      node.requestFocus();
      await t.pumpAndSettle();
      await t.tap(row('events'));
      await t.pump();
      h.change(() => h.reduce = true);
      await t.pump();
      await t.pump();
      expect(motion(t).indicatorRect, motion(t).rectOf('events'));
      h.change(() {
        h.suite = InteractionSuite.glow;
        h.light = true;
      });
      await t.pumpAndSettle();
      expect(focus(t, 'notice'), same(node));
      expect(motion(t).indicatorRect, motion(t).rectOf('events'));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, false);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      '$suite scroll, reordered groups, removed selection and empty list',
      (t) async {
        final h = await mount(t, suite);
        h.change(() => h.groups = [for (var i = 0; i < 18; i++) 'item$i']);
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          row('item17'),
          120,
          scrollable: find.byType(Scrollable),
        );
        await t.tap(row('item17'));
        await t.pumpAndSettle();
        expect(motion(t).indicatorRect, motion(t).rectOf('item17'));
        h.change(() {
          h.groups = ['item17', 'item2'];
        });
        await t.pumpAndSettle();
        expect(motion(t).indicatorRect, motion(t).rectOf('item17'));
        h.change(() => h.groups = ['item2']);
        await t.pumpAndSettle();
        expect(motion(t).indicatorRect, isNull);
        h.change(() => h.groups = []);
        await t.pumpAndSettle();
        expect(h.calls, ['item17']);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('$suite row dimensions and custom icons remain native size', (
      t,
    ) async {
      await mount(t, suite);
      expect(t.getSize(row('notice')).height, 46);
      final icons = find.descendant(
        of: row('notice'),
        matching: find.byType(StarBridgeIcon),
      );
      expect(icons, findsOneWidget);
      expect(
        t.widget<StarBridgeIcon>(icons).semantic,
        StarBridgeIconSemantic.tools,
      );
      expect(t.widget<StarBridgeIcon>(icons).size, 18);
    });

    testWidgets(
      '$suite real menu workspace retains draft on navigation and rejected save',
      (t) async {
        size(t, const Size(1440, 900));
        final port = Port();
        // Use one real owner and one storage fixture; navigation never owns saving.
        final owner = MenuSettingsDraft(port);
        await owner.initialize();
        final page = MenuSettingsWorkspace(draft: owner);
        final frame = GlobalKey();
        await t.pumpWidget(
          workspaceApp(RepaintBoundary(key: frame, child: page), suite),
        );
        await t.pumpAndSettle();
        await capture(t, frame, '${suite.name}-menu-workspace');
        owner.change({
          'widgets': const MenuDesktopWidgets(hangar: false).toMap(),
        });
        await t.pumpAndSettle();
        final edited = Map<String, Object?>.of(owner.settings);
        await t.tap(row('toolbar', 'menu-group'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        await capture(t, frame, '${suite.name}-menu-switch');
        await t.pumpAndSettle();
        expect(owner.dirty, isTrue);
        expect(owner.settings, edited);
        expect(port.writes, 0);
        port.failSave = true;
        expect(await owner.save(), false);
        await t.pumpAndSettle();
        await t.tap(row('display', 'menu-group'));
        await t.pumpAndSettle();
        expect(owner.settings, edited);
        expect(owner.dirty, isTrue);
        expect(port.writes, 1);
        port.failSave = false;
        expect(await owner.save(), true);
        await t.pumpAndSettle();
        expect(owner.dirty, isFalse);
        expect(port.writes, 2);
        await t.pumpWidget(const SizedBox());
        owner.dispose();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite real overlay workspace navigation keeps saved settings',
      (t) async {
        size(t, const Size(1440, 900));
        final port = Workspace();
        final module = OverlayWorkspaceModule(port);
        await module.initialize();
        await t.pumpWidget(
          workspaceApp(OverlayWorkspacePage(module: module), suite),
        );
        await t.pumpAndSettle();
        module.updateSetting('showNotice', false);
        await t.pumpAndSettle();
        final settings = module.projection.value.settings;
        final runtimeBefore = List.of(port.runtimeActions);
        await t.tap(row('members'));
        await t.pumpAndSettle();
        await t.tap(row('notice'));
        await t.pumpAndSettle();
        expect(module.projection.value.settings, settings);
        // The edit saved on its own; navigating writes nothing more.
        expect(port.mutations.single.settings!['showNotice'], false);
        expect(port.runtimeActions, runtimeBefore);
        expect(module.projection.value.dirty, isFalse);
        await t.pumpWidget(const SizedBox());
        module.dispose();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('$suite real category navigation review frames', (t) async {
      final h = await mount(t, suite);
      await capture(t, h.boundary, '${suite.name}-idle');
      await t.tap(row('events'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await capture(t, h.boundary, '${suite.name}-switch');
      await t.pumpAndSettle();
    });
  }
}
