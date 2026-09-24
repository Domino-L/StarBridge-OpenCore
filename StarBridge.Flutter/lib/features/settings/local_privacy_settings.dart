import 'community_sharing.dart';

/// WPF dual-axis choices. These values do not assert a server-side grant.
final class LocalPrivacySettings {
  LocalPrivacySettings({
    required this.publicationEnabled,
    required this.fleetFields,
    required this.fleetAdministratorsCanView,
    required this.fleetAllMembersCanView,
    required List<String> fleetVisibilityGroupIds,
    required this.roomFields,
    required this.roomAllMembersCanView,
    this.hideLowConfidenceLocation,
    List<CommunitySharingScope>? communities,
  }) : communities = communities == null
           ? null
           : CommunitySharingScope.validate(communities),
       fleetVisibilityGroupIds = List.unmodifiable(fleetVisibilityGroupIds) {
    if (fleetFields < 0 ||
        fleetFields > 63 ||
        roomFields < 0 ||
        roomFields > 63 ||
        fleetVisibilityGroupIds.length > 12 ||
        fleetVisibilityGroupIds.any(
          (id) =>
              id.isEmpty ||
              id.length > 128 ||
              id.trim() != id ||
              id.runes.any((c) => c < 32 || (c >= 127 && c <= 159)),
        ) ||
        fleetVisibilityGroupIds.map((id) => id.toLowerCase()).toSet().length !=
            fleetVisibilityGroupIds.length) {
      throw const FormatException('Invalid local privacy settings.');
    }
  }

  // Corresponds to Core.PlayerSharedStateFields; all six bits are independent.
  static const presence = 1,
      ship = 2,
      location = 4,
      server = 8,
      sharedEvents = 16,
      personalHangar = 32;
  final bool publicationEnabled;
  final int fleetFields;
  final bool fleetAdministratorsCanView;
  final bool fleetAllMembersCanView;
  final List<String> fleetVisibilityGroupIds;
  final int roomFields;
  final bool roomAllMembersCanView;
  final bool? hideLowConfidenceLocation;
  bool get effectiveHideLowConfidenceLocation =>
      hideLowConfidenceLocation ?? true;
  final List<CommunitySharingScope>? communities;

  LocalPrivacySettings copyWith({
    bool? publicationEnabled,
    int? fleetFields,
    bool? fleetAdministratorsCanView,
    bool? fleetAllMembersCanView,
    int? roomFields,
    bool? roomAllMembersCanView,
    bool? hideLowConfidenceLocation,
    List<CommunitySharingScope>? communities,
  }) => LocalPrivacySettings(
    publicationEnabled: publicationEnabled ?? this.publicationEnabled,
    fleetFields: fleetFields ?? this.fleetFields,
    fleetAdministratorsCanView:
        fleetAdministratorsCanView ?? this.fleetAdministratorsCanView,
    fleetAllMembersCanView:
        fleetAllMembersCanView ?? this.fleetAllMembersCanView,
    fleetVisibilityGroupIds: fleetVisibilityGroupIds,
    roomFields: roomFields ?? this.roomFields,
    roomAllMembersCanView: roomAllMembersCanView ?? this.roomAllMembersCanView,
    hideLowConfidenceLocation:
        hideLowConfidenceLocation ?? this.hideLowConfidenceLocation,
    communities: communities ?? this.communities,
  );

  static LocalPrivacySettings get editorDefaults => LocalPrivacySettings(
    publicationEnabled: true,
    fleetFields: 0,
    fleetAdministratorsCanView: false,
    fleetAllMembersCanView: true,
    fleetVisibilityGroupIds: const [],
    roomFields: 15,
    roomAllMembersCanView: true,
  );

  Map<String, Object?> toJson() => {
    'publicationEnabled': publicationEnabled,
    'fleet': {
      'fields': fleetFields,
      'administratorsCanView': fleetAdministratorsCanView,
      'allMembersCanView': fleetAllMembersCanView,
      'visibilityGroupIds': fleetVisibilityGroupIds,
    },
    'room': {'fields': roomFields, 'allMembersCanView': roomAllMembersCanView},
    if (hideLowConfidenceLocation != null)
      'hideLowConfidenceLocation': hideLowConfidenceLocation,
    if (communities != null)
      'communities': communities!.map((s) => s.toJson()).toList(),
  };

  static LocalPrivacySettings fromJson(Map<String, Object?> value) {
    final fleet = (value['fleet'] as Map).cast<String, Object?>();
    final room = (value['room'] as Map).cast<String, Object?>();
    if (!_exactKeys(value, [
          'publicationEnabled',
          'fleet',
          'room',
          if (value.containsKey('hideLowConfidenceLocation'))
            'hideLowConfidenceLocation',
          if (value.containsKey('communities')) 'communities',
        ]) ||
        !_exactKeys(fleet, const [
          'fields',
          'administratorsCanView',
          'allMembersCanView',
          'visibilityGroupIds',
        ]) ||
        !_exactKeys(room, const ['fields', 'allMembersCanView'])) {
      throw const FormatException('Unknown privacy contract.');
    }
    return LocalPrivacySettings(
      publicationEnabled: value['publicationEnabled'] as bool,
      fleetFields: fleet['fields'] as int,
      fleetAdministratorsCanView: fleet['administratorsCanView'] as bool,
      fleetAllMembersCanView: fleet['allMembersCanView'] as bool,
      fleetVisibilityGroupIds: (fleet['visibilityGroupIds'] as List)
          .cast<String>(),
      roomFields: room['fields'] as int,
      roomAllMembersCanView: room['allMembersCanView'] as bool,
      hideLowConfidenceLocation: value['hideLowConfidenceLocation'] as bool?,
      communities: value.containsKey('communities')
          ? (value['communities'] as List)
                .map(
                  (s) => CommunitySharingScope.fromJson(
                    (s as Map).cast<String, Object?>(),
                  ),
                )
                .toList()
          : null,
    );
  }

  static bool _exactKeys(Map<String, Object?> value, List<String> keys) =>
      value.length == keys.length && keys.every(value.containsKey);
}

final class LocalPrivacySnapshot {
  const LocalPrivacySnapshot({
    required this.revision,
    this.savedAt,
    this.settings,
  });
  final int revision;
  final DateTime? savedAt;
  // Null is not consent, even though the editor may offer WPF default choices.
  final LocalPrivacySettings? settings;
}
