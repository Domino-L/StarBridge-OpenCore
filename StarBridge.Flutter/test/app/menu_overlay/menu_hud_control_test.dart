import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_header.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_session.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/friends/social_layout_test.dart' show app, size;

void main() {
  for (final entry in {
    const Locale('zh', 'CN'): ['切换信息浮层', '打开信息浮层', '关闭信息浮层'],
    const Locale('zh', 'TW'): ['切換資訊浮層', '開啟資訊浮層', '關閉資訊浮層'],
    const Locale('en'): [
      'Toggle information overlay',
      'Open information overlay',
      'Close information overlay',
    ],
  }.entries) {
    testWidgets('header reflects actual HUD state in ${entry.key}', (
      tester,
    ) async {
      size(tester, const Size(1800, 1000));
      var calls = 0;
      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: entry.key,
                child: MenuBridgeHeader(
                  onDismiss: () {},
                  onHud: () => calls++,
                  hudEnabled: [null, false, true][i],
                  hudBusy: i == 2,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(entry.value[i]), findsOneWidget);
        final action = tester.widget<BridgeMenuAction>(
          find.byKey(const ValueKey('menu-toggle-hud')),
        );
        expect(action.onPressed == null, i == 2);
      }
      expect(calls, 0);
    });
  }
  testWidgets('dock active follows HUD state and pending toggle is disabled', (
    tester,
  ) async {
    size(tester, const Size(1600, 1100));
    for (final enabled in [false, true]) {
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            onFeatureVisible: (_, _) {},
            onFeatureAction: (_, _, _) {},
            features: {
              'hud': MenuFeatureView(
                'ready',
                hudEnabled: enabled,
                busy: enabled,
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final marker = tester.widget<Container>(
        find.byKey(const ValueKey('menu-open-overlay')),
      );
      expect(marker.color, enabled ? BridgeInk.blue : Colors.transparent);
      final action = tester.widget<BridgeMenuAction>(
        find.byKey(const ValueKey('menu-tool-overlay')),
      );
      expect(action.onPressed == null, enabled);
      expect(find.byKey(const ValueKey('menu-panel-hud')), findsNothing);
    }
  });
  testWidgets(
    'borrowed runtime toggles once, tracks external state, preserves language and has no poller',
    (tester) async {
      final port = _Port();
      final owner = OverlayWorkspaceModule(port);
      await owner.initialize();
      await owner.refreshRuntime('en');
      final views = <Map<String, Object?>>[];
      final session = MenuHudSession(owner, null, views.add)..show(true);
      await tester.pump();
      final baseline = port.actions.length;
      await tester.pump(const Duration(minutes: 1));
      expect(port.actions.length, baseline);
      expect(views.last['hudEnabled'], false);
      session.act('toggle', '');
      session.act('toggle', '');
      await tester.pump();
      expect(
        port.actions.where((a) => a == OverlayRuntimeAction.open).length,
        1,
      );
      expect(views.last['hudEnabled'], true);
      expect(
        port.languages.skip(1).every((language) => language == 'en'),
        true,
      );
      await owner.closeRuntime('en');
      expect(views.last['hudEnabled'], false);
      port.hold = Completer<void>();
      session.act('toggle', '');
      session.show(false);
      port.hold!.complete();
      await tester.pump();
      expect(
        port.actions.where((a) => a == OverlayRuntimeAction.open).length,
        1,
      );
      session.dispose();
      owner.dispose();
    },
  );
  testWidgets(
    'failed runtime read produces visible localized notice, no write',
    (tester) async {
      final port = _Port();
      final owner = OverlayWorkspaceModule(port);
      await owner.initialize();
      await owner.refreshRuntime('en');
      final views = <Map<String, Object?>>[];
      final session = MenuHudSession(owner, null, views.add)..show(true);
      await tester.pump();
      port.fail = true;
      session.act('toggle', '');
      await tester.pump();
      expect(views.last['notice'], contains('Could not complete'));
      expect(views.last['hudEnabled'], isNull);
      expect(port.actions, isNot(contains(OverlayRuntimeAction.open)));
      session.dispose();
      owner.dispose();
    },
  );
}

final class _Port implements OverlayWorkspacePort {
  bool enabled = false;
  bool fail = false;
  Completer<void>? hold;
  final actions = <OverlayRuntimeAction>[];
  final languages = <String>[];
  @override
  Future<OverlayWorkspaceSnapshot> read() async =>
      OverlayWorkspaceSnapshot.available(
        revision: 1,
        storageState: 'ready',
        activePresetId: 'fixture',
        renderMode: 'NativeComposition',
        appearances: [],
        presets: [],
        settings: settings(),
        layout: [],
        hotkey: const OverlayWorkspaceHotkey(
          binding: 'Alt+O',
          enabled: true,
          runtimeState: 'registered',
        ),
      );
  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    actions.add(action);
    languages.add(language);
    if (hold != null) await hold!.future;
    if (fail) return const OverlayRuntimeSnapshot.unavailable();
    if (action == OverlayRuntimeAction.open) enabled = true;
    if (action == OverlayRuntimeAction.close) enabled = false;
    return OverlayRuntimeSnapshot(
      windowState: enabled ? 'open' : 'closed',
      isVisible: enabled,
      appliedRevision: 1,
      hotkeyState: 'registered',
      followGameState: 'disabled',
      requestedSkin: 'Default',
      effectiveSkin: 'Default',
      usedFallbackSkin: false,
    );
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) => throw UnimplementedError();
  @override
  Future<void> close() async {}
}
