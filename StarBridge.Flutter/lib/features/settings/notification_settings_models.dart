import 'package:flutter/foundation.dart';

enum NotificationSettingsAvailability {
  loading,
  signedOut,
  unavailable,
  available,
}

enum NotificationSettingsOperation { none, saving }

enum NotificationSettingsFailure {
  hostUnavailable,
  readFailed,
  writeFailed,
  writeConflict,
  invalidResponse,
}

enum NotificationSettingsWriteOutcome { completed, failed }

enum DesktopNotificationPosition { topLeft, bottomLeft, topRight, bottomRight }

enum NotificationSoundAvailability { notImplemented, unavailable, available }

enum NotificationPreviewMode { fullContent, sourceOnly, hiddenDetails }

enum NotificationSourceKind {
  officialFleet,
  community,
  room,
  operation,
  friends,
  directMessages,
}

enum NotificationSourceMode { normal, importantOnly, doNotDisturb }

@immutable
final class NotificationSoundSettings {
  const NotificationSoundSettings({
    required this.availability,
    required this.enabled,
  });

  const NotificationSoundSettings.notImplemented()
    : availability = NotificationSoundAvailability.notImplemented,
      enabled = false;

  final NotificationSoundAvailability availability;
  final bool enabled;

  NotificationSoundSettings copyWith({bool? enabled}) =>
      NotificationSoundSettings(
        availability: availability,
        enabled: enabled ?? this.enabled,
      );
}

@immutable
final class NotificationChannelSettings {
  const NotificationChannelSettings({
    this.inAppEnabled = true,
    required this.windowsDesktopEnabled,
    required this.directMessageWindowsEnabled,
    required this.overlayEnabled,
    required this.desktopPosition,
    required this.sound,
  });

  factory NotificationChannelSettings.newDevice() =>
      const NotificationChannelSettings(
        windowsDesktopEnabled: true,
        directMessageWindowsEnabled: false,
        overlayEnabled: true,
        desktopPosition: DesktopNotificationPosition.bottomRight,
        sound: NotificationSoundSettings.notImplemented(),
      );

  final bool windowsDesktopEnabled;
  final bool inAppEnabled;
  final bool directMessageWindowsEnabled;
  final bool overlayEnabled;
  final DesktopNotificationPosition desktopPosition;
  final NotificationSoundSettings sound;

  NotificationChannelSettings copyWith({
    bool? inAppEnabled,
    bool? windowsDesktopEnabled,
    bool? directMessageWindowsEnabled,
    bool? overlayEnabled,
    DesktopNotificationPosition? desktopPosition,
    NotificationSoundSettings? sound,
  }) => NotificationChannelSettings(
    inAppEnabled: inAppEnabled ?? this.inAppEnabled,
    windowsDesktopEnabled: windowsDesktopEnabled ?? this.windowsDesktopEnabled,
    directMessageWindowsEnabled:
        directMessageWindowsEnabled ?? this.directMessageWindowsEnabled,
    overlayEnabled: overlayEnabled ?? this.overlayEnabled,
    desktopPosition: desktopPosition ?? this.desktopPosition,
    sound: sound ?? this.sound,
  );
}

@immutable
final class NotificationSourceRule {
  const NotificationSourceRule({
    required this.sourceRef,
    required this.kind,
    required this.displayName,
    required this.contextLabel,
    required this.mode,
    this.logoImageData,
  });

  final String sourceRef;
  final NotificationSourceKind kind;
  final String displayName;
  final String contextLabel;
  final NotificationSourceMode mode;
  final String? logoImageData;

  NotificationSourceRule copyWith({NotificationSourceMode? mode}) =>
      NotificationSourceRule(
        sourceRef: sourceRef,
        kind: kind,
        displayName: displayName,
        contextLabel: contextLabel,
        mode: mode ?? this.mode,
        logoImageData: logoImageData,
      );
}

@immutable
final class PlayerActivityNotificationSettings {
  const PlayerActivityNotificationSettings({
    required this.enabled,
    required this.includeOfficialFleet,
    required this.includeFriends,
    required this.includeCurrentRoom,
    required this.notifyOnline,
    required this.notifyOffline,
    required this.notifyGameStarted,
    required this.notifyGameStopped,
    required this.backgroundOnly,
    required this.reduceInGame,
  });

  factory PlayerActivityNotificationSettings.migratedDefault() =>
      const PlayerActivityNotificationSettings(
        enabled: false,
        includeOfficialFleet: true,
        includeFriends: false,
        includeCurrentRoom: false,
        notifyOnline: true,
        notifyOffline: false,
        notifyGameStarted: true,
        notifyGameStopped: false,
        backgroundOnly: true,
        reduceInGame: true,
      );

  final bool enabled;
  final bool includeOfficialFleet;
  final bool includeFriends;
  final bool includeCurrentRoom;
  final bool notifyOnline;
  final bool notifyOffline;
  final bool notifyGameStarted;
  final bool notifyGameStopped;
  final bool backgroundOnly;
  final bool reduceInGame;

  int get audienceCount => [
    includeOfficialFleet,
    includeFriends,
    includeCurrentRoom,
  ].where((value) => value).length;

  int get eventCount => [
    notifyOnline,
    notifyOffline,
    notifyGameStarted,
    notifyGameStopped,
  ].where((value) => value).length;

  PlayerActivityNotificationSettings copyWith({
    bool? enabled,
    bool? includeOfficialFleet,
    bool? includeFriends,
    bool? includeCurrentRoom,
    bool? notifyOnline,
    bool? notifyOffline,
    bool? notifyGameStarted,
    bool? notifyGameStopped,
    bool? backgroundOnly,
    bool? reduceInGame,
  }) => PlayerActivityNotificationSettings(
    enabled: enabled ?? this.enabled,
    includeOfficialFleet: includeOfficialFleet ?? this.includeOfficialFleet,
    includeFriends: includeFriends ?? this.includeFriends,
    includeCurrentRoom: includeCurrentRoom ?? this.includeCurrentRoom,
    notifyOnline: notifyOnline ?? this.notifyOnline,
    notifyOffline: notifyOffline ?? this.notifyOffline,
    notifyGameStarted: notifyGameStarted ?? this.notifyGameStarted,
    notifyGameStopped: notifyGameStopped ?? this.notifyGameStopped,
    backgroundOnly: backgroundOnly ?? this.backgroundOnly,
    reduceInGame: reduceInGame ?? this.reduceInGame,
  );
}

@immutable
final class ContinuousPlayReminderSettings {
  const ContinuousPlayReminderSettings({
    required this.enabled,
    required this.firstReminderMinutes,
    required this.repeatReminderMinutes,
  });

  factory ContinuousPlayReminderSettings.migratedDefault() =>
      const ContinuousPlayReminderSettings(
        enabled: true,
        firstReminderMinutes: 120,
        repeatReminderMinutes: 120,
      );

  static const supportedFirstReminderMinutes = <int>[60, 90, 120, 180];
  static const supportedRepeatReminderMinutes = <int>[60, 120];

  final bool enabled;
  final int firstReminderMinutes;
  final int repeatReminderMinutes;

  ContinuousPlayReminderSettings copyWith({
    bool? enabled,
    int? firstReminderMinutes,
    int? repeatReminderMinutes,
  }) => ContinuousPlayReminderSettings(
    enabled: enabled ?? this.enabled,
    firstReminderMinutes: firstReminderMinutes ?? this.firstReminderMinutes,
    repeatReminderMinutes: repeatReminderMinutes ?? this.repeatReminderMinutes,
  );
}

@immutable
final class NotificationSettingsValue {
  NotificationSettingsValue({
    this.localInAppOnly = false,
    this.desktopDeliveryAvailable = false,
    this.directMessageDeliveryAvailable = false,
    this.overlayDeliveryAvailable = false,
    required this.channels,
    required List<NotificationSourceRule> sourceRules,
    required this.previewMode,
    required this.playerActivity,
    required this.continuousPlay,
  }) : sourceRules = List.unmodifiable(sourceRules);

  factory NotificationSettingsValue.reviewDefaults({
    required List<NotificationSourceRule> sourceRules,
  }) => NotificationSettingsValue(
    channels: NotificationChannelSettings.newDevice(),
    sourceRules: sourceRules,
    previewMode: NotificationPreviewMode.sourceOnly,
    playerActivity: PlayerActivityNotificationSettings.migratedDefault(),
    continuousPlay: ContinuousPlayReminderSettings.migratedDefault(),
  );

  final NotificationChannelSettings channels;
  final bool localInAppOnly;
  final bool desktopDeliveryAvailable;
  final bool directMessageDeliveryAvailable;
  final bool overlayDeliveryAvailable;
  final List<NotificationSourceRule> sourceRules;
  final NotificationPreviewMode previewMode;
  final PlayerActivityNotificationSettings playerActivity;
  final ContinuousPlayReminderSettings continuousPlay;

  NotificationSettingsValue copyWith({
    NotificationChannelSettings? channels,
    List<NotificationSourceRule>? sourceRules,
    NotificationPreviewMode? previewMode,
    PlayerActivityNotificationSettings? playerActivity,
    ContinuousPlayReminderSettings? continuousPlay,
  }) => NotificationSettingsValue(
    localInAppOnly: localInAppOnly,
    desktopDeliveryAvailable: desktopDeliveryAvailable,
    directMessageDeliveryAvailable: directMessageDeliveryAvailable,
    overlayDeliveryAvailable: overlayDeliveryAvailable,
    channels: channels ?? this.channels,
    sourceRules: sourceRules ?? this.sourceRules,
    previewMode: previewMode ?? this.previewMode,
    playerActivity: playerActivity ?? this.playerActivity,
    continuousPlay: continuousPlay ?? this.continuousPlay,
  );

  NotificationSettingsValue updateSourceMode(
    String sourceRef,
    NotificationSourceMode mode,
  ) => copyWith(
    sourceRules: [
      for (final rule in sourceRules)
        if (rule.sourceRef == sourceRef) rule.copyWith(mode: mode) else rule,
    ],
  );
}

@immutable
final class NotificationSettingsSnapshot {
  const NotificationSettingsSnapshot.signedOut()
    : availability = NotificationSettingsAvailability.signedOut,
      settings = null,
      revision = null,
      allowEditing = false,
      failure = null;

  const NotificationSettingsSnapshot.unavailable({
    this.failure = NotificationSettingsFailure.hostUnavailable,
  }) : availability = NotificationSettingsAvailability.unavailable,
       settings = null,
       revision = null,
       allowEditing = false;

  const NotificationSettingsSnapshot.available({
    required this.settings,
    required this.revision,
    this.allowEditing = true,
  }) : availability = NotificationSettingsAvailability.available,
       failure = null;

  final NotificationSettingsAvailability availability;
  final NotificationSettingsValue? settings;
  final int? revision;
  final bool allowEditing;
  final NotificationSettingsFailure? failure;
}

@immutable
final class NotificationSettingsWriteResult {
  const NotificationSettingsWriteResult.completed(this.snapshot)
    : outcome = NotificationSettingsWriteOutcome.completed,
      failure = null;

  const NotificationSettingsWriteResult.failed(this.failure)
    : outcome = NotificationSettingsWriteOutcome.failed,
      snapshot = null;

  final NotificationSettingsWriteOutcome outcome;
  final NotificationSettingsSnapshot? snapshot;
  final NotificationSettingsFailure? failure;
}

@immutable
final class NotificationSettingsProjection {
  const NotificationSettingsProjection.loading()
    : availability = NotificationSettingsAvailability.loading,
      settings = null,
      revision = null,
      allowEditing = false,
      operation = NotificationSettingsOperation.none,
      failure = null;

  const NotificationSettingsProjection._({
    required this.availability,
    required this.settings,
    required this.revision,
    required this.allowEditing,
    required this.operation,
    required this.failure,
  });

  factory NotificationSettingsProjection.fromSnapshot(
    NotificationSettingsSnapshot snapshot,
  ) => NotificationSettingsProjection._(
    availability: snapshot.availability,
    settings: snapshot.settings,
    revision: snapshot.revision,
    allowEditing: snapshot.allowEditing,
    operation: NotificationSettingsOperation.none,
    failure: snapshot.failure,
  );

  final NotificationSettingsAvailability availability;
  final NotificationSettingsValue? settings;
  final int? revision;
  final bool allowEditing;
  final NotificationSettingsOperation operation;
  final NotificationSettingsFailure? failure;

  bool get canEdit =>
      availability == NotificationSettingsAvailability.available &&
      allowEditing &&
      operation == NotificationSettingsOperation.none;

  NotificationSettingsProjection copyWith({
    NotificationSettingsOperation? operation,
    NotificationSettingsFailure? failure,
    bool clearFailure = false,
  }) => NotificationSettingsProjection._(
    availability: availability,
    settings: settings,
    revision: revision,
    allowEditing: allowEditing,
    operation: operation ?? this.operation,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}
