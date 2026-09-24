import 'package:flutter/foundation.dart';

enum ConnectionVisualState { normal, pending, limited, disconnected, stale }

enum ConnectionStatusDomain { host, game, identity, network }

enum GamePresenceState { unknown, notRunning, running }

@immutable
final class ConnectionIssueProjection {
  const ConnectionIssueProjection({
    required this.domain,
    required this.titleKey,
    required this.detailKey,
    required this.state,
  }) : assert(state != ConnectionVisualState.normal);

  final ConnectionStatusDomain domain;
  final String titleKey;
  final String detailKey;
  final ConnectionVisualState state;
}

@immutable
final class OverlaySceneOption {
  const OverlaySceneOption({required this.id, required this.labelKey, this.label, this.enabled = true});

  final String id;
  final String labelKey;
  final String? label;
  final bool enabled;
}

@immutable
final class OverlaySceneProjection {
  const OverlaySceneProjection({
    required this.options,
    required this.preferredSceneId,
    required this.actualSceneId,
    required this.canChange,
    this.fallbackReasonKey,
  });

  final List<OverlaySceneOption> options;
  final String? preferredSceneId;
  final String? actualSceneId;
  final bool canChange;
  final String? fallbackReasonKey;

  OverlaySceneOption? optionById(String? id) {
    if (id == null) {
      return null;
    }
    for (final option in options) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }

  OverlaySceneProjection copyWith({
    String? preferredSceneId,
    String? actualSceneId,
    bool? canChange,
    String? fallbackReasonKey,
  }) {
    return OverlaySceneProjection(
      options: options,
      preferredSceneId: preferredSceneId ?? this.preferredSceneId,
      actualSceneId: actualSceneId ?? this.actualSceneId,
      canChange: canChange ?? this.canChange,
      fallbackReasonKey: fallbackReasonKey,
    );
  }
}

@immutable
final class ShellChromeProjection {
  const ShellChromeProjection({
    required this.overlay,
    required this.accountLabel,
    required this.presenceKey,
    required this.syncKey,
    required this.friendAttentionCount,
    required this.notificationCount,
    this.accountSignedIn = false,
    this.accountAvatarImageData,
    this.accountBusy = false,
    this.connectionIssueUsesAccountAction = false,
    this.connectionIssue,
    this.accountIssue,
    this.gamePresence = GamePresenceState.unknown,
    this.gameVersion,
  });

  final ConnectionIssueProjection? connectionIssue;
  final ConnectionIssueProjection? accountIssue;
  final OverlaySceneProjection overlay;
  final String accountLabel;
  final String? accountAvatarImageData;
  final String presenceKey;
  final GamePresenceState gamePresence;
  final String? gameVersion;
  String get gamePresenceKey => switch (gamePresence) {
    GamePresenceState.running => 'presence.inGame',
    GamePresenceState.notRunning => 'presence.notInGame',
    GamePresenceState.unknown => 'presence.gameUnknown',
  };
  String get displayPresenceKey =>
      accountSignedIn && gamePresence == GamePresenceState.running
      ? 'presence.inGame'
      : presenceKey;
  final String syncKey;
  final int friendAttentionCount;
  final int notificationCount;
  final bool accountSignedIn;
  final bool accountBusy;
  final bool connectionIssueUsesAccountAction;

  ShellChromeProjection copyWith({
    OverlaySceneProjection? overlay,
    String? accountLabel,
    String? accountAvatarImageData,
    bool clearAccountAvatar = false,
    String? presenceKey,
    GamePresenceState? gamePresence,
    String? gameVersion,
    bool clearGameVersion = false,
    String? syncKey,
    int? friendAttentionCount,
    int? notificationCount,
    bool? accountSignedIn,
    bool? accountBusy,
    bool? connectionIssueUsesAccountAction,
    ConnectionIssueProjection? connectionIssue,
    bool clearConnectionIssue = false,
    ConnectionIssueProjection? accountIssue,
    bool clearAccountIssue = false,
  }) {
    return ShellChromeProjection(
      overlay: overlay ?? this.overlay,
      accountLabel: accountLabel ?? this.accountLabel,
      accountAvatarImageData: clearAccountAvatar ? null : accountAvatarImageData ?? this.accountAvatarImageData,
      presenceKey: presenceKey ?? this.presenceKey,
      gamePresence: gamePresence ?? this.gamePresence,
      gameVersion: clearGameVersion ? null : gameVersion ?? this.gameVersion,
      syncKey: syncKey ?? this.syncKey,
      friendAttentionCount: friendAttentionCount ?? this.friendAttentionCount,
      notificationCount: notificationCount ?? this.notificationCount,
      accountSignedIn: accountSignedIn ?? this.accountSignedIn,
      accountBusy: accountBusy ?? this.accountBusy,
      connectionIssueUsesAccountAction:
          connectionIssueUsesAccountAction ??
          this.connectionIssueUsesAccountAction,
      connectionIssue: clearConnectionIssue
          ? null
          : connectionIssue ?? this.connectionIssue,
      accountIssue: clearAccountIssue
          ? null
          : accountIssue ?? this.accountIssue,
    );
  }
}
