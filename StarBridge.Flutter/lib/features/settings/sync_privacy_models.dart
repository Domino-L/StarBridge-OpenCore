import 'package:flutter/foundation.dart';

enum SyncPrivacyAvailability { loading, signedOut, unavailable, available }

enum SyncPrivacyOperation { none, saving, refreshing }

enum SyncPrivacyFailure {
  hostUnavailable,
  readFailed,
  writeFailed,
  writeConflict,
  invalidResponse,
}

enum SyncPrivacyWriteOutcome { completed, failed }

@immutable
final class FriendVisibilityDefaults {
  const FriendVisibilityDefaults({
    required this.presence,
    required this.serverRelation,
    required this.serverDetails,
    required this.ship,
    required this.location,
    required this.lastOnline,
  });

  const FriendVisibilityDefaults.newAccount()
    : presence = true,
      serverRelation = true,
      serverDetails = false,
      ship = false,
      location = false,
      lastOnline = true;

  final bool presence;
  final bool serverRelation;
  final bool serverDetails;
  final bool ship;
  final bool location;
  final bool lastOnline;

  int get enabledCount => <bool>[
    presence,
    serverRelation,
    serverDetails,
    ship,
    location,
    lastOnline,
  ].where((value) => value).length;

  FriendVisibilityDefaults copyWith({
    bool? presence,
    bool? serverRelation,
    bool? serverDetails,
    bool? ship,
    bool? location,
    bool? lastOnline,
  }) => FriendVisibilityDefaults(
    presence: presence ?? this.presence,
    serverRelation: serverRelation ?? this.serverRelation,
    serverDetails: serverDetails ?? this.serverDetails,
    ship: ship ?? this.ship,
    location: location ?? this.location,
    lastOnline: lastOnline ?? this.lastOnline,
  );
}

@immutable
final class ActivityEventSharing {
  const ActivityEventSharing({
    required this.enabled,
    required this.presence,
    required this.server,
    required this.ship,
    required this.location,
    required this.life,
  });

  final bool enabled;
  final bool presence;
  final bool server;
  final bool ship;
  final bool location;
  final bool life;

  ActivityEventSharing copyWith({
    bool? enabled,
    bool? presence,
    bool? server,
    bool? ship,
    bool? location,
    bool? life,
  }) => ActivityEventSharing(
    enabled: enabled ?? this.enabled,
    presence: presence ?? this.presence,
    server: server ?? this.server,
    ship: ship ?? this.ship,
    location: location ?? this.location,
    life: life ?? this.life,
  );
}

@immutable
final class SocialPrivacySettings {
  const SocialPrivacySettings({
    required this.allowFriendRequests,
    required this.allowStrangerDirectMessages,
    required this.recentlyPlayedDiscoverable,
    required this.hideLowConfidenceLocation,
  });

  final bool allowFriendRequests;
  final bool allowStrangerDirectMessages;
  final bool recentlyPlayedDiscoverable;
  final bool hideLowConfidenceLocation;

  SocialPrivacySettings copyWith({
    bool? allowFriendRequests,
    bool? allowStrangerDirectMessages,
    bool? recentlyPlayedDiscoverable,
    bool? hideLowConfidenceLocation,
  }) => SocialPrivacySettings(
    allowFriendRequests: allowFriendRequests ?? this.allowFriendRequests,
    allowStrangerDirectMessages:
        allowStrangerDirectMessages ?? this.allowStrangerDirectMessages,
    recentlyPlayedDiscoverable:
        recentlyPlayedDiscoverable ?? this.recentlyPlayedDiscoverable,
    hideLowConfidenceLocation:
        hideLowConfidenceLocation ?? this.hideLowConfidenceLocation,
  );
}

@immutable
final class SyncPrivacySettingsValue {
  const SyncPrivacySettingsValue({
    required this.realtimeSyncEnabled,
    required this.hasActiveCollaboration,
    required this.friendDefaults,
    required this.eventSharing,
    required this.social,
  });

  final bool realtimeSyncEnabled;
  final bool hasActiveCollaboration;
  final FriendVisibilityDefaults friendDefaults;
  final ActivityEventSharing eventSharing;
  final SocialPrivacySettings social;

  SyncPrivacySettingsValue copyWith({
    bool? realtimeSyncEnabled,
    bool? hasActiveCollaboration,
    FriendVisibilityDefaults? friendDefaults,
    ActivityEventSharing? eventSharing,
    SocialPrivacySettings? social,
  }) => SyncPrivacySettingsValue(
    realtimeSyncEnabled: realtimeSyncEnabled ?? this.realtimeSyncEnabled,
    hasActiveCollaboration:
        hasActiveCollaboration ?? this.hasActiveCollaboration,
    friendDefaults: friendDefaults ?? this.friendDefaults,
    eventSharing: eventSharing ?? this.eventSharing,
    social: social ?? this.social,
  );
}

@immutable
final class SyncPrivacySnapshot {
  const SyncPrivacySnapshot.signedOut()
    : availability = SyncPrivacyAvailability.signedOut,
      settings = null,
      revision = null,
      allowEditing = false,
      failure = null;

  const SyncPrivacySnapshot.unavailable({
    this.failure = SyncPrivacyFailure.hostUnavailable,
  }) : availability = SyncPrivacyAvailability.unavailable,
       settings = null,
       revision = null,
       allowEditing = false;

  const SyncPrivacySnapshot.available({
    required this.settings,
    required this.revision,
    this.allowEditing = true,
  }) : availability = SyncPrivacyAvailability.available,
       failure = null;

  final SyncPrivacyAvailability availability;
  final SyncPrivacySettingsValue? settings;
  final int? revision;
  final bool allowEditing;
  final SyncPrivacyFailure? failure;
}

@immutable
final class SyncPrivacyWriteResult {
  const SyncPrivacyWriteResult.completed(this.snapshot)
    : outcome = SyncPrivacyWriteOutcome.completed,
      failure = null;

  const SyncPrivacyWriteResult.failed(this.failure)
    : outcome = SyncPrivacyWriteOutcome.failed,
      snapshot = null;

  final SyncPrivacyWriteOutcome outcome;
  final SyncPrivacySnapshot? snapshot;
  final SyncPrivacyFailure? failure;
}

@immutable
final class SyncPrivacyProjection {
  const SyncPrivacyProjection.loading()
    : availability = SyncPrivacyAvailability.loading,
      settings = null,
      revision = null,
      allowEditing = false,
      operation = SyncPrivacyOperation.none,
      failure = null;

  const SyncPrivacyProjection._({
    required this.availability,
    required this.settings,
    required this.revision,
    required this.allowEditing,
    required this.operation,
    required this.failure,
  });

  factory SyncPrivacyProjection.fromSnapshot(SyncPrivacySnapshot snapshot) =>
      SyncPrivacyProjection._(
        availability: snapshot.availability,
        settings: snapshot.settings,
        revision: snapshot.revision,
        allowEditing: snapshot.allowEditing,
        operation: SyncPrivacyOperation.none,
        failure: snapshot.failure,
      );

  final SyncPrivacyAvailability availability;
  final SyncPrivacySettingsValue? settings;
  final int? revision;
  final bool allowEditing;
  final SyncPrivacyOperation operation;
  final SyncPrivacyFailure? failure;

  bool get canEdit =>
      availability == SyncPrivacyAvailability.available &&
      allowEditing &&
      operation == SyncPrivacyOperation.none;

  SyncPrivacyProjection copyWith({
    SyncPrivacyOperation? operation,
    bool? allowEditing,
    SyncPrivacyFailure? failure,
    bool clearFailure = false,
  }) => SyncPrivacyProjection._(
    availability: availability,
    settings: settings,
    revision: revision,
    allowEditing: allowEditing ?? this.allowEditing,
    operation: operation ?? this.operation,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}
