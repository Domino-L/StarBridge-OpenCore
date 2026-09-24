import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../features/overlay_settings/overlay_settings_module.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../preferences/app_preferences.dart';
import '../preferences/app_preferences_projection.dart';
import '../localization/app_strings.dart';
import '../presence/connected_manual_presence.dart';
import '../shell/chrome/shell_chrome_projection.dart';
import 'tray_quick_panel.dart';
import 'tray_surface_coordinator.dart';
import 'tray_surface_snapshot.dart';

/// One projection for the auxiliary surface. All writes reuse owning modules.
class TrayApplicationBinding {
  TrayApplicationBinding({
    required this.preferences,
    required this.chrome,
    required this.overlay,
    required this.openOverlaySettings,
    this.presence,
  }) {
    _listeners = [
      preferences,
      chrome,
      overlay.projection,
      if (overlay.workspace != null) overlay.workspace!.projection,
      if (presence != null) presence!.source.controller,
    ];
    for (final item in _listeners) {
      item.addListener(_changed);
    }
    _changed();
    _coordinator = TraySurfaceCoordinator(
      snapshot: _snapshot,
      refresh: overlay.synchronize,
      openOverlaySettings: openOverlaySettings,
      toggleOverlay: () async {
        final workspace = overlay.workspace;
        if (workspace != null) {
          final state = workspace.projection.value;
          final language = preferences.value.effective.locale.languageCode;
          final completed = state.runtime.isVisible
              ? await workspace.closeRuntime(language)
              : state.runtime.failed
              ? await workspace.retryRuntime(language)
              : await workspace.openRuntime(language);
          if (!completed) throw StateError('Overlay unavailable');
          return;
        }
        final value = overlay.projection.value;
        if (!value.canEdit ||
            value.settings == null ||
            !await overlay.save(
              value.settings!.copyWith(enabled: !value.settings!.enabled),
            )) {
          throw StateError('Overlay unavailable');
        }
      },
      setPresence: presence == null
          ? null
          : (mode) async {
              final control = presence!.source.controller;
              await control.select(mode);
              if (control.failed || control.snapshot.confirmedMode != mode) {
                throw StateError('Unconfirmed presence');
              }
            },
    );
    _releaseWatch = overlay.watch();
  }
  final ValueListenable<AppPreferencesProjection> preferences;
  final ValueListenable<ShellChromeProjection> chrome;
  final OverlaySettingsModule overlay;
  final ConnectedManualPresence? presence;
  final Future<void> Function() openOverlaySettings;
  late final List<Listenable> _listeners;
  late final TraySurfaceCoordinator _coordinator;
  late final VoidCallback _releaseWatch;
  final _snapshot = ValueNotifier(
    const TraySurfaceSnapshot(scope: 0, state: TrayQuickPanelState()),
  );
  Object? _scope;
  // A binding-local nonce also rejects a stale auxiliary view after rebinding.
  // Stay exactly representable across JSON and native channel number codecs.
  final _scopeIds = Random.secure();
  int _generation = 0;
  void _changed() {
    final p = preferences.value.effective;
    final o = overlay.projection.value;
    final workspace = overlay.workspace?.projection.value;
    final c = chrome.value;
    final scene = c.overlay.optionById(c.overlay.actualSceneId);
    final manual = presence?.source.controller;
    final nextScope = manual?.snapshot.scope;
    if (_generation == 0 || nextScope != _scope) {
      _scope = nextScope;
      int candidate;
      do {
        candidate =
            (_scopeIds.nextInt(1 << 26) << 26) | _scopeIds.nextInt(1 << 26);
      } while (candidate == 0 || candidate == _generation);
      _generation = candidate;
    }
    _snapshot.value = TraySurfaceSnapshot(
      scope: _generation,
      state: TrayQuickPanelState(
        runtime: TrayRuntimeState.running,
        scene: scene == null
            ? c.overlay.fallbackReasonKey?.startsWith('overlay.source.') != true ? null : AppStrings.resolve(p.locale).text(c.overlay.fallbackReasonKey!)
            : scene.label ?? AppStrings.resolve(p.locale).text(scene.labelKey),
        overlay: workspace != null
            ? !workspace.available || !workspace.runtime.available
                  ? TrayOverlayState.unavailable
                  : workspace.runtime.isVisible
                  ? TrayOverlayState.enabled
                  : TrayOverlayState.disabled
            : o.settings == null
            ? TrayOverlayState.unavailable
            : o.settings!.enabled
            ? TrayOverlayState.enabled
            : TrayOverlayState.disabled,
      ),
      presence: manual?.snapshot.confirmedMode,
      canChangePresence: manual?.canChange ?? false,
      canToggleOverlay: workspace != null
          ? workspace.available &&
                workspace.runtime.available &&
                !workspace.busy
          : o.canEdit,
      locale: p.locale.toLanguageTag(),
      dark: p.appearanceMode == AppearanceMode.dark,
      reduceMotion: p.motionPreference == MotionPreference.reduce,
      styleId: p.designStyleId,
      automaticKey: c.displayPresenceKey,
    );
  }

  void dispose() {
    _releaseWatch();
    for (final item in _listeners) {
      item.removeListener(_changed);
    }
    _coordinator.dispose();
    _snapshot.dispose();
  }
}
