import 'package:flutter/foundation.dart';

enum ConnectionVisualState { normal, pending, limited, disconnected, stale }

enum ConnectionStatusDomain { host, game, identity, network }

enum ConnectionIssueAction { retry, restoreOnline }

enum GamePresenceState { unknown, notRunning, running }

@immutable
final class ConnectionIssueProjection {
  const ConnectionIssueProjection({
    required this.domain,
    required this.titleKey,
    required this.detailKey,
    required this.state,
    this.action = ConnectionIssueAction.retry,
  }) : assert(state != ConnectionVisualState.normal);

  final ConnectionStatusDomain domain;
  final String titleKey;
  final String detailKey;
  final ConnectionVisualState state;
  final ConnectionIssueAction action;

  @override
  bool operator ==(Object other) =>
      other is ConnectionIssueProjection &&
      other.domain == domain &&
      other.titleKey == titleKey &&
      other.detailKey == detailKey &&
      other.state == state &&
      other.action == action;

  @override
  int get hashCode => Object.hash(domain, titleKey, detailKey, state, action);
}

@immutable
final class OverlaySceneOption {
  const OverlaySceneOption({
    required this.id,
    required this.labelKey,
    this.label,
    this.enabled = true,
  });

  final String id;
  final String labelKey;
  final String? label;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is OverlaySceneOption &&
      other.id == id &&
      other.labelKey == labelKey &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, labelKey, label, enabled);
}

@immutable
final class OverlaySceneProjection {
  const OverlaySceneProjection({
    required this.options,
    required this.preferredSceneId,
    required this.actualSceneId,
    required this.canChange,
    this.fallbackReasonKey,
    this.selectionOrigin = 'account',
  });

  final List<OverlaySceneOption> options;
  final String? preferredSceneId;
  final String? actualSceneId;
  final bool canChange;
  final String? fallbackReasonKey;
  final String selectionOrigin;

  @override
  bool operator ==(Object other) =>
      other is OverlaySceneProjection &&
      listEquals(other.options, options) &&
      other.preferredSceneId == preferredSceneId &&
      other.actualSceneId == actualSceneId &&
      other.canChange == canChange &&
      other.fallbackReasonKey == fallbackReasonKey &&
      other.selectionOrigin == selectionOrigin;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(options),
    preferredSceneId,
    actualSceneId,
    canChange,
    fallbackReasonKey,
    selectionOrigin,
  );

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
      selectionOrigin: selectionOrigin,
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
    this.accountIdentityUnconfirmed = false,
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
  // Presentation only: uncertainty is not evidence of logout or authentication.
  final bool accountIdentityUnconfirmed;
  final bool accountBusy;
  final bool connectionIssueUsesAccountAction;

  /// By content: the top bar, account menu and home page all listen, so a poll
  /// that found nothing new must not rebuild them and draw a frame.
  @override
  bool operator ==(Object other) =>
      other is ShellChromeProjection &&
      other.connectionIssue == connectionIssue &&
      other.accountIssue == accountIssue &&
      other.overlay == overlay &&
      other.accountLabel == accountLabel &&
      other.accountAvatarImageData == accountAvatarImageData &&
      other.presenceKey == presenceKey &&
      other.gamePresence == gamePresence &&
      other.gameVersion == gameVersion &&
      other.syncKey == syncKey &&
      other.friendAttentionCount == friendAttentionCount &&
      other.notificationCount == notificationCount &&
      other.accountSignedIn == accountSignedIn &&
      other.accountIdentityUnconfirmed == accountIdentityUnconfirmed &&
      other.accountBusy == accountBusy &&
      other.connectionIssueUsesAccountAction ==
          connectionIssueUsesAccountAction;

  @override
  int get hashCode => Object.hash(
    connectionIssue,
    accountIssue,
    overlay,
    accountLabel,
    accountAvatarImageData,
    presenceKey,
    gamePresence,
    gameVersion,
    syncKey,
    friendAttentionCount,
    notificationCount,
    accountSignedIn,
    accountIdentityUnconfirmed,
    accountBusy,
    connectionIssueUsesAccountAction,
  );

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
    bool? accountIdentityUnconfirmed,
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
      accountAvatarImageData: clearAccountAvatar
          ? null
          : accountAvatarImageData ?? this.accountAvatarImageData,
      presenceKey: presenceKey ?? this.presenceKey,
      gamePresence: gamePresence ?? this.gamePresence,
      gameVersion: clearGameVersion ? null : gameVersion ?? this.gameVersion,
      syncKey: syncKey ?? this.syncKey,
      friendAttentionCount: friendAttentionCount ?? this.friendAttentionCount,
      notificationCount: notificationCount ?? this.notificationCount,
      accountSignedIn: accountSignedIn ?? this.accountSignedIn,
      accountIdentityUnconfirmed:
          accountIdentityUnconfirmed ?? this.accountIdentityUnconfirmed,
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
