import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_quick_global.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_quick_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_session.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import '../../features/friends/social_layout_test.dart' show app;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_visor_layout_test.dart'
    show defaults, visor;

/// 11-11 user ("按预览改"): Alt+M → 信息浮层 gets a global section with calm
/// display and the visor's depth, saved straight to the active preset like the
/// module toggles. The overall opacity went with its retirement (11-12 user:
/// "全局里的整体透明度应该去掉，这是之前遗留的废弃项").
void main() {
  Future<
    (OverlayWorkspaceModule, _Port, List<Map<String, Object?>>, MenuHudSession)
  >
  start(WidgetTester tester, OverlayWorkspaceSettings saved) async {
    final port = _Port(saved);
    final owner = OverlayWorkspaceModule(port);
    await owner.initialize();
    final views = <Map<String, Object?>>[];
    final session = MenuHudSession(owner, null, views.add)..show(true);
    await tester.pump();
    return (owner, port, views, session);
  }

  Map<String, Object?> quick(List<Map<String, Object?>> views) =>
      views.last['quick']! as Map<String, Object?>;

  testWidgets(
    'the wire carries calm display and the depth; no overall opacity',
    (tester) async {
      final (owner, _, views, session) = await start(
        tester,
        visor().withValue('calmDisplay', 'On').withValue('opacity', 0.8),
      );
      expect(quick(views)['global'], {
        'calm': true,
        'tilt': visor()['visorTilt'],
      });
      final parsed = MenuFeatureView.parse(views.last).hudQuick!.global!;
      expect(parsed.calm, isTrue);
      expect(parsed.tilt, visor()['visorTilt']);
      session.dispose();
      owner.dispose();

      final (other, _, otherViews, otherSession) = await start(
        tester,
        settings({'skin': 'Default', 'opacity': 1.0}),
      );
      // 0.7.3 puts the other appearances away: a saved "Default" still shows
      // the visor, so its depth is offered too
      expect((quick(otherViews)['global'] as Map).containsKey('tilt'), isTrue);
      otherSession.dispose();
      other.dispose();
    },
  );

  test(
    'an old value outside the range shows clamped; a wrong type is refused',
    () {
      // an older engine's wire may still carry the opacity: it is ignored
      final view = MenuHudQuickGlobal.parse({
        'calm': false,
        'opacity': 0.05,
        'tilt': 75,
      })!;
      expect(view.tilt, MenuHudQuickGlobal.maxTilt);
      expect(
        () => MenuHudQuickGlobal.parse({'calm': 'yes'}),
        throwsFormatException,
      );
      expect(
        () => MenuHudQuickGlobal.parse({'calm': true, 'tilt': '1'}),
        throwsFormatException,
      );
      expect(MenuHudQuickGlobal.parse(null), isNull);
    },
  );

  testWidgets('each one saves straight to the preset', (tester) async {
    final (owner, port, views, session) = await start(tester, visor());
    session.act('calm', '');
    await tester.pump();
    expect(port.mutations.last.kind, OverlayWorkspaceMutationKind.saveActive);
    expect(port.mutations.last.settings!['calmDisplay'], 'On');
    expect((quick(views)['global'] as Map)['calm'], true);
    session.act('calm', '');
    await tester.pump();
    expect(port.mutations.last.settings!['calmDisplay'], 'Off');

    // the retired overall opacity is no longer an action
    final before = port.mutations.length;
    session.act('opacity', '0.60');
    await tester.pump();
    expect(port.mutations, hasLength(before));
    session.act('tilt', '25');
    await tester.pump();
    expect(port.mutations.last.settings!['visorTilt'], 25.0);
    // out of range is held to it; nonsense is ignored
    session.act('tilt', '90');
    await tester.pump();
    expect(port.mutations.last.settings!['visorTilt'], 60.0);
    final count = port.mutations.length;
    session.act('tilt', 'x');
    session.act('tilt', '60');
    await tester.pump();
    expect(port.mutations, hasLength(count), reason: 'nothing to save');
    expect(owner.projection.value.dirty, isFalse);
    session.dispose();
    owner.dispose();
  });

  testWidgets('a failed save leaves no draft and says so', (tester) async {
    final (owner, port, views, session) = await start(tester, visor());
    port.fail = OverlaySettingsFailure.writeFailed;
    session.act('tilt', '30');
    await tester.pump();
    expect(owner.projection.value.dirty, isFalse);
    expect((quick(views)['note'] as Map)['kind'], 'failed');
    session.dispose();
    owner.dispose();
  });

  testWidgets('the controls send one intent each, a slider when let go', (
    tester,
  ) async {
    final sent = <(String, String)>[];
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 600,
          child: MenuHudQuickGlobalControls(
            global: const MenuHudQuickGlobal(calm: false, tilt: 15),
            enabled: true,
            text: (key) => key,
            onAction: (key, value) => sent.add((key, value)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-hud-quick-calm')));
    await tester.pump();
    expect(sent, [('calm', '')]);
    StarBridgeSlider slider(String key) => tester.widget<StarBridgeSlider>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(StarBridgeSlider),
      ),
    );
    expect(find.byKey(const ValueKey('menu-hud-quick-opacity')), findsNothing);
    slider('menu-hud-quick-tilt').onChanged!(20);
    await tester.pump();
    expect(sent, hasLength(1), reason: 'nothing while dragging');
    slider('menu-hud-quick-tilt').onChangeEnd!(22);
    expect(sent.skip(1), [('tilt', '22')]);
    expect(tester.takeException(), isNull);
  });
}

final class _Port implements OverlayWorkspacePort {
  _Port(this.current);

  int revision = 1;
  OverlayWorkspaceSettings current;
  final mutations = <OverlayWorkspaceMutation>[];
  OverlaySettingsFailure? fail;
  late List<OverlayWorkspaceLayoutItem> layout = defaults();

  @override
  Future<OverlayWorkspaceSnapshot> read() async =>
      OverlayWorkspaceSnapshot.available(
        revision: revision,
        storageState: 'ready',
        activePresetId: 'default',
        renderMode: 'NativeComposition',
        appearances: const [],
        presets: [
          OverlayWorkspacePreset(
            id: 'default',
            name: '默认预设',
            isActive: true,
            storageState: 'ready',
            settings: current,
            layout: const [],
          ),
        ],
        settings: current,
        layout: layout,
        hotkey: const OverlayWorkspaceHotkey(
          binding: 'Alt+O',
          enabled: true,
          runtimeState: 'registered',
        ),
      );

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    mutations.add(mutation);
    if (fail case final failure?) {
      return OverlayWorkspaceWriteResult.failed(failure);
    }
    revision++;
    if (mutation.kind == OverlayWorkspaceMutationKind.saveActive) {
      current = mutation.settings!;
      layout = mutation.layout!;
    }
    return OverlayWorkspaceWriteResult.completed(await read());
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async => const OverlayRuntimeSnapshot(
    windowState: 'open',
    isVisible: true,
    appliedRevision: 1,
    hotkeyState: 'registered',
    followGameState: 'disabled',
    requestedSkin: 'Visor',
    effectiveSkin: 'Visor',
    usedFallbackSkin: false,
  );

  @override
  Future<void> close() async {}
}
