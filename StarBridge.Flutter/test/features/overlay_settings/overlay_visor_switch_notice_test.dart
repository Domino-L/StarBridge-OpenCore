import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_switch_notice.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;
import 'overlay_appearance_preview_page_test.dart' show Workspace;

// 0.7.3 overlay v2 (user, 11-07): for users of the earlier overlay, the first visit
// to the overlay settings says once that the overlay was upgraded and its settings are back to defaults.
final class _Port implements OverlayWorkspacePort, OverlayVisorNoticePort {
  _Port({required this.notice});
  final _base = Workspace();
  bool notice;
  int dismissals = 0;
  void Function()? onDismiss;

  @override
  Future<OverlayWorkspaceSnapshot> read() async {
    final s = _base.snapshot;
    return OverlayWorkspaceSnapshot.available(
      revision: s.revision!,
      storageState: s.storageState!,
      activePresetId: s.activePresetId!,
      renderMode: s.renderMode!,
      appearances: s.appearances,
      hotkey: s.hotkey!,
      settings: s.settings!,
      layout: s.layout,
      presets: s.presets,
      appearanceOptionsEnabled: s.appearanceOptionsEnabled,
      appearanceConfigurations: s.appearanceConfigurations,
      appearanceOptions: s.appearanceOptions,
      visorSwitchNotice: notice,
    );
  }

  @override
  Future<void> dismissVisorNotice() async {
    onDismiss?.call();
    dismissals++;
    notice = false;
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) => _base.apply(mutation, expectedRevision: expectedRevision);

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) => _base.executeRuntime(action, language: language, draft: draft);

  @override
  Future<void> close() async {}
}

void main() {
  test('reading only shows the line; "知道了" tells the Host', () async {
    final port = _Port(notice: true);
    final first = OverlayWorkspaceModule(port);
    await first.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(first.visorNotice.visible.value, isTrue);
    expect(port.dismissals, 0, reason: 'a read must not write');
    await first.refresh();
    expect(
      first.visorNotice.visible.value,
      isTrue,
      reason: 'stays for this visit',
    );
    expect(port.dismissals, 0);
    first.visorNotice.close();
    await Future<void>.delayed(Duration.zero);
    expect(first.visorNotice.visible.value, isFalse);
    expect(port.dismissals, 1);
    first.dispose();

    final later = OverlayWorkspaceModule(port);
    await later.initialize();
    expect(later.visorNotice.visible.value, isFalse);
    later.dispose();
  });

  for (final save in [true, false]) {
    final after = save ? 'saving' : 'discarding';
    test('with unsaved edits the close waits for $after', () async {
      final port = _Port(notice: true);
      final module = OverlayWorkspaceModule(port);
      await module.initialize();
      var idleAtConfirm = true;
      port.onDismiss = () => idleAtConfirm =
          !module.projection.value.dirty && !module.projection.value.busy;
      final notice =
          module.projection.value.settings!.values['showNotice'] == true;
      module.updateSetting('showNotice', !notice);
      expect(module.projection.value.dirty, isTrue);
      module.visorNotice.close();
      await Future<void>.delayed(Duration.zero);
      expect(module.visorNotice.visible.value, isFalse);
      if (save) {
        expect(await module.save(), isTrue);
      } else {
        module.discardChanges();
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(port.dismissals, 1, reason: 'the confirmation is not lost');
      expect(idleAtConfirm, isTrue, reason: 'never races a pending save');
      module.dispose();

      final later = OverlayWorkspaceModule(port);
      await later.initialize();
      expect(later.visorNotice.visible.value, isFalse, reason: 'not again');
      later.dispose();
    });
  }

  test('no line when the Host reports no upgrade', () async {
    final port = _Port(notice: false);
    final module = OverlayWorkspaceModule(port);
    await module.initialize();
    expect(module.visorNotice.visible.value, isFalse);
    expect(port.dismissals, 0);
    module.dispose();
  });

  testWidgets('the settings page shows the line above the settings', (
    tester,
  ) async {
    await tester.runAsync(loadFonts);
    size(tester, const Size(1440, 900));
    final module = OverlayWorkspaceModule(_Port(notice: true));
    await module.initialize();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: app(OverlayWorkspacePage(module: module)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-visor-switch-notice')),
      findsOneWidget,
    );
    expect(find.text('浮层升级到新版，设置已恢复默认'), findsOneWidget);
    await capture(tester, key, 'overlay-visor-switch-notice');
    await tester.tap(
      find.byKey(const Key('overlay-visor-switch-notice-close')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-visor-switch-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    module.dispose();
  });
}
