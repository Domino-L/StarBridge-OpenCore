import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_workspace.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_overlay_settings.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_display_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_feature.dart';
import 'package:starbridge_flutter/features/overlay_settings/in_memory_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_workspace.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_help.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_scroll.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_display_preferences.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_save_bar.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class Port implements MenuWindowPreferencesPort {
  int reads = 0, writes = 0;
  bool fail = false, failSave = false;
  MenuWindowPreferences value = MenuWindowPreferences.defaults;
  MenuWindowPreferences? submitted;
  Completer<MenuWindowPreferences>? pending;
  @override
  Future<MenuWindowPreferences> read() async {
    reads++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('unavailable');
    return value;
  }

  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    writes++;
    submitted = next;
    if (fail || failSave) throw StateError('revision conflict');
    return value = MenuWindowPreferences(
      next.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

class RetainedProbe extends StatefulWidget {
  const RetainedProbe({super.key});
  @override
  State<RetainedProbe> createState() => RetainedProbeState();
}

class RetainedProbeState extends State<RetainedProbe> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: input);
}

Future<void> category(WidgetTester tester, String name) async {
  final navigation = find.byKey(const Key('menu-group-navigation'));
  if (navigation.evaluate().isNotEmpty) {
    await tester.tap(
      find.descendant(of: navigation, matching: find.text(name)),
    );
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  test(
    'save merges unrelated external fields and keeps latest layout',
    () async {
      final port = Port();
      final draft = MenuSettingsDraft(port);
      await draft.initialize();
      final baseDisplay = MenuDisplayPreferences.fromSettings(draft.settings)!;
      draft.change(baseDisplay.change('showClock', false).toSettingsPatch());
      final remote = baseDisplay.change('showDate', false).toSettingsPatch();
      port.value = MenuWindowPreferences(
        12,
        {
          'version': 1,
          'panels': [
            {
              'id': 'friends',
              'bounds': [1, 2, 300, 400],
            },
          ],
          'open': [],
        },
        {...port.value.settings, ...remote},
      );
      expect(await draft.save(), true);
      expect(port.submitted!.revision, 12);
      expect(port.submitted!.layout['panels'], port.value.layout['panels']);
      final actual = MenuDisplayPreferences.fromSettings(port.value.settings)!;
      expect(actual.showClock, false);
      expect(actual.showDate, false);
      draft.dispose();
    },
  );
  test('conflicting field does not write or discard local edits', () async {
    final port = Port();
    final draft = MenuSettingsDraft(port);
    await draft.initialize();
    draft.change({'dimming': .6});
    port.value = MenuWindowPreferences(4, port.value.layout, {
      ...port.value.settings,
      'dimming': .7,
    });
    expect(await draft.save(), false);
    expect(draft.conflict, true);
    expect(draft.dirty, true);
    expect(port.writes, 0);
    expect(draft.settings['dimming'], .6);
    draft.dispose();
  });
  test(
    'undo redo and returning to defaults retain no false dirty state',
    () async {
      final draft = MenuSettingsDraft(Port());
      await draft.initialize();
      final display = MenuDisplayPreferences.fromSettings(draft.settings)!;
      draft.change(display.change('showClock', false).toSettingsPatch());
      expect(draft.dirty, true);
      draft.undo();
      expect(draft.dirty, false);
      expect(draft.canRedo, true);
      draft.redo();
      expect(draft.settings['showClock'], false);
      draft.change(display.toSettingsPatch());
      expect(draft.dirty, false);
      draft.change(display.change('showClock', false).toSettingsPatch());
      expect(await draft.save(), true);
      expect(draft.canUndo, false);
      expect(draft.canRedo, false);
      draft.dispose();
    },
  );
  for (final width in [1500.0, 760.0, 320.0]) {
    testWidgets('shared bottom save bar at $width preserves failed edits', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      final port = Port();
      final state = MenuSettingsDraft(port);
      await tester.pumpWidget(app(MenuSettingsWorkspace(draft: state)));
      await tester.pumpAndSettle();
      expect(find.byType(OverlaySettingsSaveBar), findsNothing);
      state.change({'showClock': false});
      await tester.pumpAndSettle();
      expect(find.byType(OverlaySettingsSaveBar), findsOneWidget);
      expect(find.text('保存更改'), findsOneWidget);
      expect(
        tester.getBottomRight(find.byType(OverlaySettingsSaveBar)).dy,
        900,
      );
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(state.dirty, false);
      await tester.tap(find.byTooltip('重做'));
      await tester.pumpAndSettle();
      port.fail = true;
      await tester.tap(find.byKey(const Key('menu-workspace-save')));
      await tester.pumpAndSettle();
      expect(state.dirty, true);
      expect(state.settings['showClock'], false);
      await tester.tap(find.byKey(const Key('menu-workspace-discard')));
      await tester.pumpAndSettle();
      expect(find.byType(OverlaySettingsSaveBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
  test('failed initial read can recover without saving defaults', () async {
    final port = Port()..fail = true;
    final draft = MenuSettingsDraft(port);
    await draft.initialize();
    expect(draft.ready, false);
    expect(draft.failed, true);
    draft.change({'showClock': false});
    expect(await draft.save(), false);
    expect(port.writes, 0);
    port.fail = false;
    await draft.reload();
    expect(draft.ready, true);
    expect(draft.failed, false);
    expect(draft.dirty, false);
    expect(port.reads, 2);
    draft.dispose();
  });
  testWidgets(
    'separate editors mount lazily and survive categories and resizing',
    (tester) async {
      size(tester, const Size(1500, 800));
      final draft = MenuSettingsDraft(Port());
      final key = GlobalKey<RetainedProbeState>();
      await tester.pumpWidget(
        app(
          MenuSettingsWorkspace(
            draft: draft,
            shortcuts: RetainedProbe(key: key),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(key.currentState, isNull);
      await category(tester, '快捷键');
      final original = key.currentState!;
      original.input.text = 'unsaved shortcut';
      await category(tester, '显示与操作');
      await category(tester, '快捷键');
      expect(key.currentState, same(original));
      tester.view.physicalSize = const Size(760, 800);
      await tester.pumpAndSettle();
      expect(key.currentState, same(original));
      expect(original.input.text, 'unsaved shortcut');
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );
  test(
    'initial read deduplicates and saves recheck CAS and preserve layout',
    () async {
      final port = Port()
        ..value = const MenuWindowPreferences(
          12,
          {
            'version': 1,
            'panels': [
              {
                'id': 'friends',
                'bounds': [1, 2, 320, 400],
              },
            ],
            'open': [],
          },
          {
            'showClock': true,
            'showContext': true,
            'dimming': .5,
            'snapWindows': true,
          },
        );
      final draft = MenuSettingsDraft(port);
      await draft.initialize();
      await draft.initialize();
      expect(port.reads, 1);
      draft.change({'showClock': false});
      port.failSave = true;
      expect(await draft.save(), false);
      expect(draft.dirty, true);
      expect(draft.settings['showClock'], false);
      await draft.reload();
      expect(port.reads, 2);
      expect(port.submitted!.revision, 12);
      expect(port.submitted!.layout, port.value.layout);
      expect(port.submitted!.settings['snapWindows'], true);
      port.failSave = false;
      expect(await draft.save(), true);
      expect(draft.dirty, false);
      expect(port.value.revision, 13);
      draft.change({'showClock': true});
      draft.discard();
      expect(draft.settings['showClock'], false);
      await draft.reload();
      expect(port.reads, 4);
      draft.dispose();
    },
  );
  test('late read cannot restore a disposed account draft', () async {
    final port = Port()..pending = Completer<MenuWindowPreferences>();
    final draft = MenuSettingsDraft(port);
    final future = draft.initialize();
    draft.dispose();
    port.pending!.complete(MenuWindowPreferences.defaults);
    await future;
    expect(draft.ready, false);
  });
  testWidgets(
    'category switches retain one draft and preview has no authority',
    (tester) async {
      size(tester, const Size(1100, 900));
      final port = Port();
      final draft = MenuSettingsDraft(port);
      await tester.pumpWidget(app(MenuSettingsWorkspace(draft: draft)));
      await tester.pumpAndSettle();
      await category(tester, '显示与操作');
      final editor = tester.widget<MenuDisplayEditor>(
        find.byType(MenuDisplayEditor),
      );
      editor.onChanged(editor.value.change('showClock', false));
      await tester.pumpAndSettle();
      final preview = tester.widget<MenuBridgePreview>(
        find.byType(MenuBridgePreview),
      );
      expect(preview.localToolsController!.showClock, false);
      expect(preview.localCall, isNull);
      expect(preview.onFriendsAction, isNull);
      expect(preview.onCommsVisible, isNull);
      expect(preview.onSettingsChanged, isNull);
      expect(preview.onFeatureAction, isNull);
      expect(preview.initialLayout, isNull);
      expect(preview.settingsPreview, true);
      expect(preview.contextValues!.last, 'presence.online');
      expect(find.text('连接待确认'), findsNothing);
      expect(
        tester
            .widget<BridgePreviewDock>(find.byType(BridgePreviewDock))
            .openPanels,
        isEmpty,
      );
      expect(
        tester
            .widget<MenuBridgeWorkspace>(find.byType(MenuBridgeWorkspace))
            .controller
            .exportLayout()['open'],
        isEmpty,
      );
      await category(tester, '浏览器');
      expect(find.byType(MenuBrowserEditor), findsOneWidget);
      await category(tester, '显示与操作');
      expect(
        tester
            .widget<MenuDisplayEditor>(find.byType(MenuDisplayEditor))
            .value
            .showClock,
        false,
      );
      expect(port.reads, 1);
      expect(port.writes, 0);
      await tester.tap(find.byKey(const Key('menu-workspace-save')));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(draft.dirty, false);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );
  testWidgets('leave guard keeps edits on cancel or failed save', (
    tester,
  ) async {
    final port = Port();
    final module = OverlaySettingsModule(InMemoryOverlaySettingsAdapter());
    final draft = MenuSettingsDraft(port);
    module.menuDraft = draft;
    await draft.initialize();
    draft.change({'showClock': false});
    bool? allowed;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              allowed = await confirmOverlayWorkspaceLeave(context, module);
            },
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-unsaved-leave-cancel')));
    await tester.pumpAndSettle();
    expect(allowed, false);
    expect(draft.dirty, true);
    port.fail = true;
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-unsaved-leave-save')));
    await tester.pumpAndSettle();
    expect(allowed, false);
    expect(draft.dirty, true);
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-unsaved-leave-discard')));
    await tester.pumpAndSettle();
    expect(allowed, true);
    expect(draft.dirty, false);
    module.dispose();
  });
  testWidgets(
    'preview uses monitor viewport and keeps windows closed at both zooms',
    (tester) async {
      size(tester, const Size(1600, 900));
      tester.view.display.size = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1.25;
      tester.view.physicalSize = const Size(2000, 1125);
      addTearDown(tester.view.display.resetSize);
      final draft = MenuSettingsDraft(Port());
      await tester.pumpWidget(app(MenuSettingsWorkspace(draft: draft)));
      await tester.pumpAndSettle();
      void check() {
        final canvas = tester.widget<SizedBox>(
          find.byKey(const Key('menu-preview-canvas')),
        );
        expect(Size(canvas.width!, canvas.height!), const Size(2048, 1152));
        final context = tester.element(find.byType(MenuBridgePreview));
        expect(MediaQuery.sizeOf(context), const Size(2048, 1152));
        expect(
          tester
              .widget<BridgePreviewDock>(find.byType(BridgePreviewDock))
              .openPanels,
          isEmpty,
        );
        expect(find.text('视觉预览 · 好友与通讯可展开 · 演示数据'), findsNothing);
      }

      check();
      await tester.tap(find.byKey(const Key('menu-preview-zoom')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-preview-actual-size')), findsOneWidget);
      check();
      await tester.tap(find.byKey(const Key('menu-preview-zoom')));
      await tester.pumpAndSettle();
      check();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );
  testWidgets(
    'inspector scrollbar is at panel edge and help uses information-overlay hierarchy',
    (tester) async {
      size(tester, const Size(1600, 900));
      final draft = MenuSettingsDraft(Port());
      await tester.pumpWidget(app(MenuSettingsWorkspace(draft: draft)));
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('menu-settings-right'));
      final scroll = find.byType(MenuSettingsScroll);
      final bar = find.descendant(of: scroll, matching: find.byType(Scrollbar));
      expect(tester.getRect(bar).right, tester.getRect(panel).right);
      final field = find.byKey(const ValueKey('menu-display-interfaceScale-0'));
      expect(tester.getRect(panel).right - tester.getRect(field).right, 24);
      expect(find.text('菜单显示与交互'), findsNothing);
      final help = find
          .descendant(of: panel, matching: find.byType(OverlaySettingsHelp))
          .first;
      final explanation = tester.widget<Text>(
        find.descendant(of: help, matching: find.byType(Text)),
      );
      final context = tester.element(help);
      expect(explanation.style!.color, context.tokens.colors.textSecondary);
      expect(
        explanation.style!.fontSize,
        Theme.of(context).textTheme.bodySmall!.fontSize,
      );
      final before = tester.getTopLeft(find.text('显示时间')).dy;
      await tester.drag(scroll, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('显示时间')).dy, lessThan(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    },
  );
  for (final width in [1600.0, 1056.0, 1216.0, 320.0]) {
    testWidgets('workspace layout at content width $width', (tester) async {
      size(tester, Size(width, 800));
      tester.view.display.size = const Size(1920, 1080);
      addTearDown(tester.view.display.resetSize);
      final draft = MenuSettingsDraft(Port());
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(MenuOverlaySettings(preview: null, draft: draft)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width >= 1280) {
        expect(
          tester.getTopLeft(find.byKey(const Key('menu-group-navigation'))).dx,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('menu-preview-stage'))).dx,
          ),
        );
        expect(
          tester.getTopLeft(find.byKey(const Key('menu-preview-stage'))).dx,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('menu-settings-right'))).dx,
          ),
        );
      } else {
        expect(find.byKey(const Key('menu-settings-expand')), findsOneWidget);
        expect(find.byType(MenuDisplayEditor), findsNothing);
      }
      await capture(tester, key, 'menu-workspace-${width.toInt()}');
      for (final name in [
        '底部工具栏',
        '窗口与恢复',
        '好友与提醒',
        '浏览器',
        '参考图',
        '截图',
        '快捷键',
      ]) {
        await category(tester, name);
        expect(tester.takeException(), isNull, reason: '$width / $name');
      }
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
    });
  }
}
