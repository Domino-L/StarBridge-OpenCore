import 'overlay_workspace_models.dart';

enum OverlayWorkspaceSceneKind { fleet, partyRoom }

final class OverlayWorkspaceSceneSelection {
  const OverlayWorkspaceSceneSelection({
    required this.kind,
    required this.isFallback,
  });

  final OverlayWorkspaceSceneKind kind;
  final bool isFallback;
}

final class OverlayWorkspaceVisibility {
  const OverlayWorkspaceVisibility({
    required this.showNotice,
    required this.showSquads,
    required this.showMembers,
    required this.showChat,
    required this.showCrosshair,
    required this.showEventNotifications,
  });

  final bool showNotice;
  final bool showSquads;
  final bool showMembers;
  final bool showChat;
  final bool showCrosshair;
  final bool showEventNotifications;

  bool isLayoutModuleVisible(String key) => switch (key) {
    'Notice' => showNotice,
    'Squads' => showSquads,
    'Members' => showMembers,
    'Chat' => showChat,
    _ => false,
  };
}

final class OverlayWorkspaceRuntimeProjection {
  const OverlayWorkspaceRuntimeProjection._();

  static OverlayWorkspaceSceneSelection resolveScene({
    required String preference,
    required bool hasCurrentPartyRoom,
  }) {
    final usePartyRoom =
        preference == 'PartyRoom' ||
        (preference == 'Auto' && hasCurrentPartyRoom);
    return usePartyRoom && hasCurrentPartyRoom
        ? const OverlayWorkspaceSceneSelection(
            kind: OverlayWorkspaceSceneKind.partyRoom,
            isFallback: false,
          )
        : OverlayWorkspaceSceneSelection(
            kind: OverlayWorkspaceSceneKind.fleet,
            isFallback: preference == 'PartyRoom',
          );
  }

  static OverlayWorkspaceVisibility resolveVisibility(
    OverlayWorkspaceSettings settings, {
    required bool noticeHasContent,
    required bool chatHasContent,
    required bool eventNotificationsHaveContent,
  }) => OverlayWorkspaceVisibility(
    showNotice: settings['showNotice']! as bool && noticeHasContent,
    showSquads: settings['showSquads']! as bool,
    showMembers: settings['showMembers']! as bool,
    showChat: settings['showChat']! as bool && chatHasContent,
    showCrosshair: settings['showCrosshair']! as bool,
    showEventNotifications:
        settings['showEventNotifications']! as bool &&
        eventNotificationsHaveContent,
  );
}
