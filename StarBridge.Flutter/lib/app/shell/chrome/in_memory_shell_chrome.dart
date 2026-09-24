import 'package:flutter/foundation.dart';

import 'shell_chrome_port.dart';
import 'shell_chrome_projection.dart';

final class InMemoryShellChrome implements ShellChromePort {
  InMemoryShellChrome({ShellChromeProjection? initial})
    : _projection = ValueNotifier(initial ?? disconnectedProjection);

  final ValueNotifier<ShellChromeProjection> _projection;

  @override
  ValueListenable<ShellChromeProjection> get projection => _projection;

  @override
  Future<SceneSelectionResult> selectOverlayScene(String sceneId) async {
    final current = _projection.value;
    if (!current.overlay.canChange) {
      return SceneSelectionResult.hostUnavailable;
    }
    if (current.overlay.optionById(sceneId) == null) {
      return SceneSelectionResult.rejected;
    }
    _projection.value = current.copyWith(
      overlay: current.overlay.copyWith(preferredSceneId: sceneId),
    );
    return SceneSelectionResult.saved;
  }

  void replace(ShellChromeProjection projection) {
    _projection.value = projection;
  }

  static const disconnectedProjection = ShellChromeProjection(
    connectionIssue: ConnectionIssueProjection(
      domain: ConnectionStatusDomain.host,
      titleKey: 'connection.host.disconnected.title',
      detailKey: 'connection.host.disconnected.detail',
      state: ConnectionVisualState.disconnected,
    ),
    overlay: OverlaySceneProjection(
      options: [
        OverlaySceneOption(id: 'default', labelKey: 'overlay.scene.default'),
        OverlaySceneOption(id: 'room', labelKey: 'overlay.scene.room'),
        OverlaySceneOption(
          id: 'operation',
          labelKey: 'overlay.scene.operation',
        ),
      ],
      preferredSceneId: 'default',
      actualSceneId: null,
      canChange: false,
      fallbackReasonKey: 'overlay.hostUnavailable',
    ),
    accountLabel: '',
    presenceKey: 'presence.offline',
    syncKey: 'sync.hostUnavailable',
    friendAttentionCount: 0,
    notificationCount: 0,
  );

  static const connectedProjection = ShellChromeProjection(
    overlay: OverlaySceneProjection(
      options: [
        OverlaySceneOption(id: 'default', labelKey: 'overlay.scene.default'),
        OverlaySceneOption(id: 'room', labelKey: 'overlay.scene.room'),
        OverlaySceneOption(
          id: 'operation',
          labelKey: 'overlay.scene.operation',
        ),
      ],
      preferredSceneId: 'default',
      actualSceneId: 'default',
      canChange: true,
    ),
    accountLabel: 'Domino-L',
    presenceKey: 'presence.online',
    syncKey: 'sync.current',
    friendAttentionCount: 2,
    notificationCount: 2,
  );

  static const hostConnectedProjection = ShellChromeProjection(
    overlay: OverlaySceneProjection(
      options: [
        OverlaySceneOption(id: 'default', labelKey: 'overlay.scene.default'),
        OverlaySceneOption(id: 'room', labelKey: 'overlay.scene.room'),
        OverlaySceneOption(
          id: 'operation',
          labelKey: 'overlay.scene.operation',
        ),
      ],
      preferredSceneId: 'default',
      actualSceneId: null,
      canChange: false,
      fallbackReasonKey: 'overlay.capabilityUnavailable',
    ),
    accountLabel: '',
    presenceKey: 'presence.offline',
    syncKey: 'sync.current',
    friendAttentionCount: 0,
    notificationCount: 0,
  );
}
