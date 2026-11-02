import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/host_unavailable_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';

import 'overlay_settings_ux_a_test.dart' show settings;

// Realtime plan §6 (2026-10-20): with `overlay.runtime.changed` the tray and
// settings page stop polling; they read once on watch, language change and
// Host invalidation. Older Hosts keep the 10 s poll.

OverlayRuntimeSnapshot _runtime() => OverlayRuntimeSnapshot.fromMap(const {
  'schemaVersion': 1,
  'windowState': 'closed',
  'isVisible': false,
  'appliedRevision': 1,
  'hotkeyState': 'registered',
  'followGameState': 'manual',
  'requestedSkin': 'Default',
  'effectiveSkin': 'Default',
  'usedFallbackSkin': false,
  'failureCode': null,
  'retryable': false,
});

class _Port implements OverlayWorkspacePort {
  int reads = 0;

  @override
  Future<OverlayWorkspaceSnapshot> read() async {
    reads++;
    return OverlayWorkspaceSnapshot.available(
      revision: 1,
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
          settings: settings(),
          layout: const [],
        ),
      ],
      settings: settings(),
      layout: const [],
      hotkey: const OverlayWorkspaceHotkey(
        binding: 'Ctrl+Shift+O',
        enabled: true,
        runtimeState: 'registered',
      ),
    );
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async => OverlayWorkspaceWriteResult.completed(await read());

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async => _runtime();

  @override
  Future<void> close() async {}
}

final class _PushPort extends _Port implements OverlayRuntimeChangePort {
  bool supported = true;
  final changes = StreamController<OverlayRuntimeSnapshot>.broadcast();
  @override
  bool get supportsRuntimeChanges => supported;
  @override
  Stream<OverlayRuntimeSnapshot> get runtimeChanges => changes.stream;
}

void main() {
  testWidgets(
    'pushed runtime: no poll; reads on watch, language, invalidation',
    (tester) async {
      final port = _PushPort();
      final language = ValueNotifier('zh');
      final invalidations = StreamController<void>.broadcast();
      final module = OverlaySettingsModule(
        HostUnavailableOverlaySettingsAdapter(),
        workspacePort: port,
        languageChanges: language,
        language: () => language.value,
        hostInvalidations: invalidations.stream,
      );
      await module.initialize();
      await tester.pump();
      final initial = port.reads;

      // Unwatched: nothing reads.
      language.value = 'en';
      invalidations.add(null);
      await tester.pump(const Duration(seconds: 30));
      expect(port.reads, initial);

      final release = module.watch();
      await tester.pump();
      expect(port.reads, initial + 1, reason: 'settings entry reads once');
      await tester.pump(const Duration(seconds: 35));
      expect(port.reads, initial + 1, reason: 'pushes replace the 10 s poll');

      language.value = 'zh';
      await tester.pump();
      expect(port.reads, initial + 2, reason: 'language change reads once');
      language.value = 'zh';
      await tester.pump();
      expect(port.reads, initial + 2, reason: 'same language does not read');

      invalidations.add(null);
      await tester.pump();
      expect(port.reads, initial + 3, reason: 'Host invalidation reads once');

      release();
      module.dispose();
      await invalidations.close();
      language.dispose();
    },
  );

  testWidgets('older Host keeps the poll until pushes become available', (
    tester,
  ) async {
    final port = _PushPort()..supported = false;
    final module = OverlaySettingsModule(
      HostUnavailableOverlaySettingsAdapter(),
      workspacePort: port,
    );
    await module.initialize();
    final release = module.watch();
    await tester.pump();
    final watched = port.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(port.reads, watched + 1, reason: 'fallback poll');

    port.supported = true;
    await tester.pump(const Duration(seconds: 10));
    final settled = port.reads;
    await tester.pump(const Duration(seconds: 30));
    expect(port.reads, settled, reason: 'late capability stops the poll');
    release();
    module.dispose();
  });
}
