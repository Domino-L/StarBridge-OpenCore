import 'package:flutter/foundation.dart';

import 'personal_profile_models.dart'
    show
        PersonalProfileModuleLayoutItem,
        PersonalProfilePlayStyle,
        PersonalProfileSchedule,
        PersonalProfileShipSummary,
        PersonalProfileVisibility;

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
    this.favoriteShipCodes,
    this.playStyle,
    this.schedule,
    this.achievementShowcase,
    this.shipWishlist,
  });

  final String callSign;
  final String about;
  final int avatarStyle;
  final String wallpaperId;
  final PersonalProfileVisibility visibility;
  final List<PersonalProfileModuleLayoutItem> moduleLayout;

  /// Null preserves the existing selection, including unresolved remote refs.
  final List<String>? favoriteShipIds;
  final List<String>? favoriteShipCodes; // Flat legacy favorites on the wire.
  final PersonalProfilePlayStyle? playStyle;
  final PersonalProfileSchedule? schedule;
  final List<String>? achievementShowcase; // Null keeps the saved picks.
  final List<String>? shipWishlist; // Versioned page only.
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
    this.accountCallSign = false,
    this.localOnlyEdits = false,
    this.autoImportPending = false,
    this.showLocalFavoriteShips = false,
  });
  final List<PersonalProfileShipSummary> choices;
  final List<PersonalProfileShipSummary> retainedChoices;
  final List<String>? favoriteShipIds;
  final bool hangarAvailable;
  final bool remoteAvailable;
  final bool accountCallSign;
  final bool localOnlyEdits;
  final bool autoImportPending;
  final bool showLocalFavoriteShips;
  final bool needsCreation;
  final DateTime? savedAt;
  final bool partial;
  final Map<String, String> timeZones;
}
