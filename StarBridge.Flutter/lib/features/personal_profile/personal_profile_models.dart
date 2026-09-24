import 'package:flutter/foundation.dart';

enum PersonalProfileAvailability { loading, signedOut, unavailable, available }

enum PersonalProfileOperation { none, refreshing, saving }

enum PersonalProfileActionOutcome { completed, rejected, failed }

enum PersonalProfileDayGroup { weekdays, weekend }

enum PersonalProfileActivityRhythm {
  casual,
  regular,
  intensive,
  weekends,
  irregular,
}

enum PersonalProfilePresenceIntent {
  none,
  lookingForGroup,
  availableSupport,
  busy,
  doNotDisturb,
}

enum PersonalProfileVisibility {
  everyone('public', 'profile.visibility.public'),
  friendsAndMainFleet(
    'friendsAndMainFleet',
    'profile.visibility.friendsAndMainFleet',
  ),
  friendsOnly('friendsOnly', 'profile.visibility.friendsOnly'),
  friendsFleetAndOrganizations('friendsFleetAndOrganizations', 'profile.visibility.related'),
  onlyMe('private', 'profile.visibility.private');

  const PersonalProfileVisibility(this.bridgeValue, this.labelKey);

  final String bridgeValue;
  final String labelKey;

  static PersonalProfileVisibility fromBridgeValue(String? value) {
    return PersonalProfileVisibility.values.firstWhere(
      (visibility) => visibility.bridgeValue == value,
      orElse: () => PersonalProfileVisibility.onlyMe,
    );
  }
}

enum PersonalProfileModuleSize {
  one(1),
  two(2),
  three(3);

  const PersonalProfileModuleSize(this.span);

  final int span;
}

enum PersonalProfileTagCategory {
  command,
  ship,
  airCombat,
  groundCombat,
  recon,
  industry,
  medical,
  logistics,
}

enum PersonalProfileAffiliationKind { officialFleet, featuredCommunity }

abstract final class PersonalProfileModuleIds {
  static const collaborationProfile = 'collaboration-profile';
  static const favoriteShips = 'favorite-ships';
  static const hangarSummary = 'hangar-summary';
  static const skilledRoles = 'skilled-roles';
  static const supportCapabilities = 'support-capabilities';
  static const participationInterests = 'participation-interests';
  static const shipWishlist = 'ship-wishlist';

  static bool isFavorite(String id) =>
      id == favoriteShips ||
      RegExp(r'^favorite-ships-[1-9][0-9]{0,3}$').hasMatch(id);

  static String typeOf(String id) => isFavorite(id) ? favoriteShips : id;
}

@immutable
final class PersonalProfileModuleLayoutItem {
  const PersonalProfileModuleLayoutItem({
    required this.moduleId,
    required this.size,
    required this.isVisible,
    required this.position,
    this.favoriteShipIds,
  });

  final String moduleId;
  final PersonalProfileModuleSize size;
  final bool isVisible;
  final int position;

  /// Null is the pre-module selection format. Empty is an explicit selection.
  final List<String>? favoriteShipIds;

  PersonalProfileModuleLayoutItem copyWith({
    PersonalProfileModuleSize? size,
    bool? isVisible,
    int? position,
    List<String>? favoriteShipIds,
  }) {
    return PersonalProfileModuleLayoutItem(
      moduleId: moduleId,
      size: size ?? this.size,
      isVisible: isVisible ?? this.isVisible,
      position: position ?? this.position,
      favoriteShipIds: favoriteShipIds ?? this.favoriteShipIds,
    );
  }
}

@immutable
final class PersonalProfileAvailabilityWindow {
  const PersonalProfileAvailabilityWindow({
    this.dayGroup = PersonalProfileDayGroup.weekdays,
    List<int>? days,
    required this.startTime,
    required this.endTime,
    // Keep the public constructor name while retaining the old day-group default.
    // ignore: prefer_initializing_formals
  }) : _days = days;

  final PersonalProfileDayGroup dayGroup;
  final List<int>? _days;
  List<int> get days =>
      _days ??
      (dayGroup == PersonalProfileDayGroup.weekdays
          ? const [1, 2, 3, 4, 5]
          : const [6, 0]);
  final String startTime;
  final String endTime;
  bool get endsNextDay => endTime.compareTo(startTime) <= 0;

  Map<String, Object?> toJson() => {
    'days': days,
    'startTime': startTime,
    'endTime': endTime,
  };
}

@immutable
final class PersonalProfilePlayStyle {
  const PersonalProfilePlayStyle({this.roles, this.interests, this.support});
  final List<String>? roles, interests, support;
  Map<String, Object?> toJson() => {
    if (roles != null) 'roles': roles,
    if (interests != null) 'interests': interests,
    if (support != null) 'support': support,
  };
}

@immutable
final class PersonalProfileSchedule {
  const PersonalProfileSchedule({
    required this.timeZoneId,
    required this.rhythm,
    required this.windows,
  });
  final String timeZoneId;
  final PersonalProfileActivityRhythm rhythm;
  final List<PersonalProfileAvailabilityWindow> windows;
  Map<String, Object?> toJson() => {
    'timeZoneId': timeZoneId,
    'rhythm': rhythm.name,
    'windows': [for (final window in windows) window.toJson()],
  };
}

@immutable
final class PersonalProfileTagValue {
  const PersonalProfileTagValue({
    required this.labelKey,
    required this.category,
    this.isPrimary = false,
    this.displayLabel,
  });

  final String labelKey;
  final PersonalProfileTagCategory category;
  final bool isPrimary;
  final String? displayLabel;
}

@immutable
final class PersonalProfileAffiliationSummary {
  const PersonalProfileAffiliationSummary({
    required this.kind,
    required this.name,
    required this.code,
    required this.positionLabelKey,
    this.logoUrl,
    this.logoImageData,
  });

  final PersonalProfileAffiliationKind kind;
  final String name;
  final String code;
  final String positionLabelKey;

  /// Viewer-authorized HTTPS logo supplied with the current affiliation.
  final String? logoUrl;

  /// Viewer-authorized PNG/JPEG data URI supplied with the current affiliation.
  final String? logoImageData;
}

@immutable
final class PersonalProfileShipIdentity {
  const PersonalProfileShipIdentity({
    required this.runtimeId,
    required this.englishName,
    required this.simplifiedChineseName,
    required this.traditionalChineseName,
    this.catalogId,
  });

  final String runtimeId;
  final String englishName;
  final String simplifiedChineseName;
  final String traditionalChineseName;
  /// Canonical model identity, distinct from an instance or legacy runtime ID.
  final String? catalogId;
}

@immutable
final class PersonalProfileShipSummary {
  const PersonalProfileShipSummary({
    required this.identity,
    required this.manufacturer,
    required this.imageAsset,
    required this.roleKey,
    required this.crewLabel,
    required this.sizeKey,
    required this.valueLabel,
    this.valueLabelKey = 'profile.shipData.officialValue',
    this.thumbnailAsset,
    this.catalogIconKey,
    this.formerlyOwned = false,
  });

  final PersonalProfileShipIdentity identity;
  final String manufacturer;
  final String imageAsset;
  final String roleKey;
  final String crewLabel;
  final String sizeKey;
  final String valueLabel;
  final String valueLabelKey;
  final String? thumbnailAsset;
  final String? catalogIconKey;
  final bool formerlyOwned;

  PersonalProfileShipSummary withFormerOwnership(bool value) =>
      PersonalProfileShipSummary(
        identity: identity,
        manufacturer: manufacturer,
        imageAsset: imageAsset,
        roleKey: roleKey,
        crewLabel: crewLabel,
        sizeKey: sizeKey,
        valueLabel: valueLabel,
        valueLabelKey: valueLabelKey,
        thumbnailAsset: thumbnailAsset,
        catalogIconKey: catalogIconKey,
        formerlyOwned: value,
      );
}

@immutable
final class PersonalProfileHangarCategorySlice {
  const PersonalProfileHangarCategorySlice({
    required this.labelKey,
    required this.count,
    required this.category,
  });

  final String labelKey;
  final int count;
  final PersonalProfileTagCategory category;
}

@immutable
final class PersonalProfileHangarSummary {
  const PersonalProfileHangarSummary({
    required this.shipCount,
    required this.manufacturerCount,
    required this.primaryRoleKey,
    required this.estimatedValueLabel,
    required this.categories,
    required this.recentlyAddedShip,
    required this.recentlyAddedShipImageAsset,
    required this.recentlyAddedAtLabel,
    required this.sourceLabelKey,
    required this.syncedAtLabel,
    this.isAvailable = true,
    this.unresolvedFavoriteCount = 0,
    this.unpricedCount,
  });

  const PersonalProfileHangarSummary.empty({this.unresolvedFavoriteCount = 0})
    : unpricedCount = null,
      shipCount = 0,
      manufacturerCount = 0,
      primaryRoleKey = '',
      estimatedValueLabel = '',
      categories = const [],
      recentlyAddedShip = null,
      recentlyAddedShipImageAsset = '',
      recentlyAddedAtLabel = '',
      sourceLabelKey = '',
      syncedAtLabel = '',
      isAvailable = false;

  final int shipCount;
  final bool isAvailable;
  final int unresolvedFavoriteCount;
  final int? unpricedCount;
  final int manufacturerCount;
  final String primaryRoleKey;
  final String estimatedValueLabel;
  final List<PersonalProfileHangarCategorySlice> categories;
  final PersonalProfileShipIdentity? recentlyAddedShip;
  final String recentlyAddedShipImageAsset;
  final String recentlyAddedAtLabel;
  final String sourceLabelKey;
  final String syncedAtLabel;
}

@immutable
final class PersonalProfileSnapshot {
  const PersonalProfileSnapshot.signedOut()
    : availability = PersonalProfileAvailability.signedOut,
      local = null,
      allowEditing = false,
      failureKey = null,
      callSign = '',
      gameHandle = '',
      about = '',
      avatarStyle = 0,
      avatarImageData = null,
      wallpaperId = 'none',
      visibility = PersonalProfileVisibility.onlyMe,
      presenceIntent = PersonalProfilePresenceIntent.none,
      affiliations = const [],
      availabilityWindows = const [],
      timeZoneLabel = '',
      gameplayMinutes = 0,
      activityRhythm = PersonalProfileActivityRhythm.casual,
      roles = const [],
      participationInterests = const [],
      supportCapabilities = const [],
      shipWishlist = const [],
      favoriteShips = const [],
      hangarSummary = const PersonalProfileHangarSummary.empty(),
      moduleLayout = const [];

  const PersonalProfileSnapshot.unavailable({
    this.failureKey = 'profile.error.unavailable',
  }) : availability = PersonalProfileAvailability.unavailable,
       local = null,
       allowEditing = false,
       callSign = '',
       gameHandle = '',
       about = '',
       avatarStyle = 0,
       avatarImageData = null,
       wallpaperId = 'none',
       visibility = PersonalProfileVisibility.onlyMe,
       presenceIntent = PersonalProfilePresenceIntent.none,
       affiliations = const [],
       availabilityWindows = const [],
       timeZoneLabel = '',
       gameplayMinutes = 0,
       activityRhythm = PersonalProfileActivityRhythm.casual,
       roles = const [],
       participationInterests = const [],
       supportCapabilities = const [],
       shipWishlist = const [],
       favoriteShips = const [],
       hangarSummary = const PersonalProfileHangarSummary.empty(),
       moduleLayout = const [];

  const PersonalProfileSnapshot.available({
    this.avatarImageData,
    required this.callSign,
    required this.gameHandle,
    required this.about,
    required this.avatarStyle,
    required this.wallpaperId,
    required this.visibility,
    required this.presenceIntent,
    required this.affiliations,
    required this.availabilityWindows,
    required this.timeZoneLabel,
    required this.gameplayMinutes,
    required this.activityRhythm,
    required this.roles,
    required this.participationInterests,
    required this.supportCapabilities,
    required this.shipWishlist,
    required this.favoriteShips,
    required this.hangarSummary,
    required this.moduleLayout,
    this.allowEditing = true,
    this.failureKey,
    this.local,
  }) : availability = PersonalProfileAvailability.available;

  final PersonalProfileLocalView? local;
  final PersonalProfileAvailability availability;
  final bool allowEditing;
  final String? failureKey;
  final String callSign;
  final String gameHandle;
  final String about;
  final int avatarStyle;
  final String? avatarImageData;
  final String wallpaperId;
  final PersonalProfileVisibility visibility;
  final PersonalProfilePresenceIntent presenceIntent;
  final List<PersonalProfileAffiliationSummary> affiliations;
  final List<PersonalProfileAvailabilityWindow> availabilityWindows;
  final String timeZoneLabel;
  final int gameplayMinutes;
  final PersonalProfileActivityRhythm activityRhythm;
  final List<PersonalProfileTagValue> roles;
  final List<PersonalProfileTagValue> participationInterests;
  final List<PersonalProfileTagValue> supportCapabilities;
  final List<PersonalProfileTagValue> shipWishlist;
  final List<PersonalProfileShipSummary> favoriteShips;
  final PersonalProfileHangarSummary hangarSummary;
  final List<PersonalProfileModuleLayoutItem> moduleLayout;

  bool get isPublic => visibility == PersonalProfileVisibility.everyone;
}

@immutable
final class PersonalProfileProjection {
  const PersonalProfileProjection({
    this.avatarImageData,
    required this.availability,
    required this.operation,
    required this.callSign,
    required this.gameHandle,
    required this.about,
    required this.avatarStyle,
    required this.wallpaperId,
    required this.visibility,
    required this.presenceIntent,
    required this.affiliations,
    required this.availabilityWindows,
    required this.timeZoneLabel,
    required this.gameplayMinutes,
    required this.activityRhythm,
    required this.roles,
    required this.participationInterests,
    required this.supportCapabilities,
    required this.shipWishlist,
    required this.favoriteShips,
    required this.hangarSummary,
    required this.moduleLayout,
    required this.allowEditing,
    this.failureKey,
    this.local,
  });

  const PersonalProfileProjection.loading()
    : this(
        availability: PersonalProfileAvailability.loading,
        operation: PersonalProfileOperation.none,
        callSign: '',
        gameHandle: '',
        about: '',
        avatarStyle: 0,
        wallpaperId: 'none',
        visibility: PersonalProfileVisibility.onlyMe,
        presenceIntent: PersonalProfilePresenceIntent.none,
        affiliations: const [],
        availabilityWindows: const [],
        timeZoneLabel: '',
        gameplayMinutes: 0,
        activityRhythm: PersonalProfileActivityRhythm.casual,
        roles: const [],
        participationInterests: const [],
        supportCapabilities: const [],
        shipWishlist: const [],
        favoriteShips: const [],
        hangarSummary: const PersonalProfileHangarSummary.empty(),
        moduleLayout: const [],
        allowEditing: false,
      );

  final PersonalProfileAvailability availability;
  final PersonalProfileOperation operation;
  final String? avatarImageData;
  final PersonalProfileLocalView? local;
  final String callSign;
  final String gameHandle;
  final String about;
  final int avatarStyle;
  final String wallpaperId;
  final PersonalProfileVisibility visibility;
  final PersonalProfilePresenceIntent presenceIntent;
  final List<PersonalProfileAffiliationSummary> affiliations;
  final List<PersonalProfileAvailabilityWindow> availabilityWindows;
  final String timeZoneLabel;
  final int gameplayMinutes;
  final PersonalProfileActivityRhythm activityRhythm;
  final List<PersonalProfileTagValue> roles;
  final List<PersonalProfileTagValue> participationInterests;
  final List<PersonalProfileTagValue> supportCapabilities;
  final List<PersonalProfileTagValue> shipWishlist;
  final List<PersonalProfileShipSummary> favoriteShips;
  final PersonalProfileHangarSummary hangarSummary;
  final List<PersonalProfileModuleLayoutItem> moduleLayout;
  final bool allowEditing;
  final String? failureKey;

  bool get isPublic => visibility == PersonalProfileVisibility.everyone;

  bool get canEdit =>
      availability == PersonalProfileAvailability.available &&
      allowEditing &&
      operation == PersonalProfileOperation.none;

  PersonalProfileProjection copyWith({
    List<PersonalProfileAffiliationSummary>? affiliations,
    String? avatarImageData,
    PersonalProfileOperation? operation,
    String? callSign,
    String? about,
    int? avatarStyle,
    String? wallpaperId,
    PersonalProfileVisibility? visibility,
    String? failureKey,
    bool clearFailure = false,
  }) {
    return PersonalProfileProjection(
      availability: availability,
      operation: operation ?? this.operation,
      callSign: callSign ?? this.callSign,
      gameHandle: gameHandle,
      about: about ?? this.about,
      avatarStyle: avatarStyle ?? this.avatarStyle,
      avatarImageData: avatarImageData ?? this.avatarImageData,
      wallpaperId: wallpaperId ?? this.wallpaperId,
      visibility: visibility ?? this.visibility,
      presenceIntent: presenceIntent,
      affiliations: affiliations ?? this.affiliations,
      availabilityWindows: availabilityWindows,
      timeZoneLabel: timeZoneLabel,
      gameplayMinutes: gameplayMinutes,
      activityRhythm: activityRhythm,
      roles: roles,
      participationInterests: participationInterests,
      supportCapabilities: supportCapabilities,
      shipWishlist: shipWishlist,
      favoriteShips: favoriteShips,
      hangarSummary: hangarSummary,
      moduleLayout: moduleLayout,
      allowEditing: allowEditing,
      local: local,
      failureKey: clearFailure ? null : failureKey ?? this.failureKey,
    );
  }

  factory PersonalProfileProjection.fromSnapshot(
    PersonalProfileSnapshot snapshot,
  ) {
    return PersonalProfileProjection(
      availability: snapshot.availability,
      operation: PersonalProfileOperation.none,
      callSign: snapshot.callSign,
      gameHandle: snapshot.gameHandle,
      about: snapshot.about,
      avatarStyle: snapshot.avatarStyle,
      avatarImageData: snapshot.avatarImageData,
      wallpaperId: snapshot.wallpaperId,
      visibility: snapshot.visibility,
      presenceIntent: snapshot.presenceIntent,
      affiliations: List.unmodifiable(snapshot.affiliations),
      availabilityWindows: List.unmodifiable(snapshot.availabilityWindows),
      timeZoneLabel: snapshot.timeZoneLabel,
      gameplayMinutes: snapshot.gameplayMinutes,
      activityRhythm: snapshot.activityRhythm,
      roles: List.unmodifiable(snapshot.roles),
      participationInterests: List.unmodifiable(
        snapshot.participationInterests,
      ),
      supportCapabilities: List.unmodifiable(snapshot.supportCapabilities),
      shipWishlist: List.unmodifiable(snapshot.shipWishlist),
      favoriteShips: List.unmodifiable(snapshot.favoriteShips),
      hangarSummary: snapshot.hangarSummary,
      moduleLayout: List.unmodifiable(snapshot.moduleLayout),
      allowEditing: snapshot.allowEditing,
      local: snapshot.local,
      failureKey: snapshot.failureKey,
    );
  }
}

@immutable
final class PersonalProfileEdit {
  const PersonalProfileEdit({
    required this.callSign,
    required this.about,
    required this.avatarStyle,
    required this.wallpaperId,
    required this.visibility,
    required this.moduleLayout,
    this.favoriteShipIds,
    this.playStyle,
    this.schedule,
  });

  final String callSign;
  final String about;
  final int avatarStyle;
  final String wallpaperId;
  final PersonalProfileVisibility visibility;
  final List<PersonalProfileModuleLayoutItem> moduleLayout;

  /// Null preserves the existing selection, including unresolved remote refs.
  final List<String>? favoriteShipIds;
  final PersonalProfilePlayStyle? playStyle;
  final PersonalProfileSchedule? schedule;
}

@immutable
final class PersonalProfileLocalView {
  const PersonalProfileLocalView({
    required this.choices,
    required this.favoriteShipIds,
    required this.hangarAvailable,
    required this.remoteAvailable,
    this.needsCreation = false,
    this.savedAt,
    this.partial = false,
    this.timeZones = const {},
    this.retainedChoices = const [],
  });
  final List<PersonalProfileShipSummary> choices;
  final List<PersonalProfileShipSummary> retainedChoices;
  final List<String>? favoriteShipIds;
  final bool hangarAvailable;
  final bool remoteAvailable;
  final bool needsCreation;
  final DateTime? savedAt;
  final bool partial;
  final Map<String, String> timeZones;
}

@immutable
final class PersonalProfileActionResult {
  const PersonalProfileActionResult(this.outcome, {this.failureKey});

  final PersonalProfileActionOutcome outcome;
  final String? failureKey;
}
