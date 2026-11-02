import '../presence/manual_presence.dart';
import '../../features/onboarding/connection_mode_port.dart';
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
    this.interactionStyle = 'standard',
    this.automaticKey = 'presence.unknown',
    this.opening = 0,
    this.keyboard = false,
    this.connectionMode = ConnectionModeState.unsupported,
    this.canEnterOffline = false,
    this.canRestoreOnline = false,
    this.revision = 0,
  });
  final int scope, opening;
  final int revision;
  final TrayQuickPanelState state;
  final PresenceVisibility? presence;
  final ConnectionModeState connectionMode;
  final bool canEnterOffline;
  final bool canRestoreOnline;
  final bool canChangePresence, canToggleOverlay, dark, reduceMotion, keyboard;
  final String locale, styleId, automaticKey, interactionStyle;
  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'scope': scope,
    'revision': revision,
    'runtime': state.runtime.name,
    'overlay': state.overlay.name,
    'version': state.version,
    'scene': state.scene,
    'mode': presence?.name,
    'canChangePresence': canChangePresence,
    'connectionMode': connectionMode.name,
    'canEnterOffline': canEnterOffline,
    'canRestoreOnline': canRestoreOnline,
    'canToggleOverlay': canToggleOverlay,
    'locale': locale,
    'dark': dark,
    'reduceMotion': reduceMotion,
    'styleId': styleId,
    'interactionStyle': interactionStyle,
    'automaticKey': automaticKey,
  };
  static TraySurfaceSnapshot parse(Object? input) {
    if (input is! Map ||
        input['schemaVersion'] != 1 ||
        input['scope'] is! int) {
      throw const FormatException('Invalid tray snapshot');
    }
    if (input.containsKey('revision') &&
        (input['revision'] is! int ||
            (input['revision'] as int) < 0 ||
            (input['revision'] as int) > 9007199254740991)) {
      throw const FormatException('Invalid projection revision');
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
    final connectionMode = input.containsKey('connectionMode')
        ? ConnectionModeState.values
              .where((v) => v.name == input['connectionMode'])
              .firstOrNull
        : ConnectionModeState.unsupported;
    if (connectionMode == null ||
        input.containsKey('canEnterOffline') &&
            input['canEnterOffline'] is! bool ||
        input['canEnterOffline'] == true &&
            connectionMode != ConnectionModeState.online ||
        input.containsKey('canRestoreOnline') &&
            input['canRestoreOnline'] is! bool ||
        input['canRestoreOnline'] == true &&
            connectionMode != ConnectionModeState.offline) {
      throw const FormatException('Invalid connection mode');
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
      revision: input['revision'] as int? ?? 0,
      connectionMode: connectionMode,
      canEnterOffline: input['canEnterOffline'] == true,
      canRestoreOnline: input['canRestoreOnline'] == true,
      canChangePresence: flag('canChangePresence'),
      canToggleOverlay: flag('canToggleOverlay'),
      locale: text('locale') ?? 'zh-CN',
      dark: flag('dark'),
      reduceMotion: flag('reduceMotion'),
      styleId: text('styleId') ?? 'future_restraint_a',
      interactionStyle: text('interactionStyle') ?? 'standard',
      automaticKey: text('automaticKey') ?? 'presence.unknown',
      opening: input['opening'] is int ? input['opening'] as int : 0,
      keyboard: input['keyboard'] == true,
    );
  }
}
