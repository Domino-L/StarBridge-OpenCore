import '../presence/manual_presence.dart';
import 'tray_quick_panel.dart';

/// Display-only projection shared with the auxiliary view. No token, account
/// authority/subject, endpoint, local path or raw game data crosses this seam.
class TraySurfaceSnapshot {
  const TraySurfaceSnapshot({
    required this.scope,
    required this.state,
    this.presence,
    this.canChangePresence = false,
    this.canToggleOverlay = false,
    this.locale = 'zh-CN',
    this.dark = true,
    this.reduceMotion = false,
    this.styleId = 'future_restraint_a',
    this.automaticKey = 'presence.unknown',
    this.opening = 0,
    this.keyboard = false,
  });
  final int scope, opening;
  final TrayQuickPanelState state;
  final PresenceVisibility? presence;
  final bool canChangePresence, canToggleOverlay, dark, reduceMotion, keyboard;
  final String locale, styleId, automaticKey;
  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'scope': scope,
    'runtime': state.runtime.name,
    'overlay': state.overlay.name,
    'version': state.version,
    'scene': state.scene,
    'mode': presence?.name,
    'canChangePresence': canChangePresence,
    'canToggleOverlay': canToggleOverlay,
    'locale': locale,
    'dark': dark,
    'reduceMotion': reduceMotion,
    'styleId': styleId,
    'automaticKey': automaticKey,
  };
  static TraySurfaceSnapshot parse(Object? input) {
    if (input is! Map ||
        input['schemaVersion'] != 1 ||
        input['scope'] is! int) {
      throw const FormatException('Invalid tray snapshot');
    }
    String? text(String key) {
      final v = input[key];
      if (v == null) return null;
      if (v is! String || v.length > 256) {
        throw const FormatException('Invalid label');
      }
      return v;
    }

    bool flag(String key) {
      final v = input[key];
      if (v is! bool) throw const FormatException('Invalid flag');
      return v;
    }

    final runtime = TrayRuntimeState.values
        .where((v) => v.name == input['runtime'])
        .firstOrNull;
    final overlay = TrayOverlayState.values
        .where((v) => v.name == input['overlay'])
        .firstOrNull;
    final mode = PresenceVisibility.values
        .where((v) => v.name == input['mode'])
        .firstOrNull;
    if (runtime == null ||
        overlay == null ||
        (input['mode'] != null && mode == null)) {
      throw const FormatException('Invalid state');
    }
    return TraySurfaceSnapshot(
      scope: input['scope'] as int,
      state: TrayQuickPanelState(
        runtime: runtime,
        overlay: overlay,
        version: text('version'),
        scene: text('scene'),
      ),
      presence: mode,
      canChangePresence: flag('canChangePresence'),
      canToggleOverlay: flag('canToggleOverlay'),
      locale: text('locale') ?? 'zh-CN',
      dark: flag('dark'),
      reduceMotion: flag('reduceMotion'),
      styleId: text('styleId') ?? 'future_restraint_a',
      automaticKey: text('automaticKey') ?? 'presence.unknown',
      opening: input['opening'] is int ? input['opening'] as int : 0,
      keyboard: input['keyboard'] == true,
    );
  }
}
