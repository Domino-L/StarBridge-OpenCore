import 'package:flutter/foundation.dart';

import 'official_fleet_member_runtime_capabilities.dart';
export 'official_fleet_member_runtime_capabilities.dart';

enum OfficialFleetMemberDirectoryAvailability {
  idle,
  loading,
  available,
  unavailable,
}

enum OfficialFleetMemberFilter { all, online, inGame }

enum OfficialFleetMemberIdentityState { scm, starBridge, restricted }

enum OfficialFleetMemberPresence {
  unknown,
  away,
  notConnected,
  offline,
  online,
  inGame,
  invisible,
}

enum OfficialFleetRosterCoverage {
  unknown,
  completeOfficialRoster,
  scmRegisteredMembers,
  partial,
  restricted,
}

enum OfficialFleetMemberFieldState {
  value,
  unknown,
  notShared,
  notInGame,
  restricted,
  notConnected,
}

@immutable
final class OfficialFleetMemberField {
  const OfficialFleetMemberField(this.state, {this.value});

  const OfficialFleetMemberField.value(String value)
    : this(OfficialFleetMemberFieldState.value, value: value);

  final OfficialFleetMemberFieldState state;
  final String? value;
}

@immutable
final class OfficialFleetMember {
  const OfficialFleetMember({
    required this.memberRef,
    required this.callsign,
    required this.gameId,
    required this.officialRankName,
    required this.officialRankValue,
    required this.presence,
    required this.server,
    required this.ship,
    required this.location,
    required this.starBridgeConnected,
    this.avatarUrl,
    this.identityState,
    this.avatarImageData,
    this.profileTargetRef,
    this.arrivalPending = false,
    this.sharingPaused = false,
    this.isSelf = false,
    this.serverRegion,
    this.hasServerSession,
    this.locationHiddenReason,
    this.arrivalTargetCode,
  });

  final String memberRef;
  final String callsign;
  final String gameId;
  final String? avatarUrl;
  // null identifies an older Host's SCM-only projection, not confirmed linkage.
  final OfficialFleetMemberIdentityState? identityState;
  final String? avatarImageData;
  final String? profileTargetRef;
  final String? officialRankName;
  final int? officialRankValue;
  final OfficialFleetMemberPresence presence;
  final OfficialFleetMemberField server;
  final OfficialFleetMemberField ship;
  final OfficialFleetMemberField location;
  // null means that the source has not confirmed application enrollment.
  final bool? starBridgeConnected;
  final bool arrivalPending;
  final bool sharingPaused;
  // Host marks only the viewer's own Java-verified linked row; never a name match.
  final bool isSelf;
  final String? serverRegion, locationHiddenReason, arrivalTargetCode;
  final bool? hasServerSession;

  OfficialFleetMember withPresence(OfficialFleetMemberPresence value) =>
      value == presence
      ? this
      : OfficialFleetMember(
          memberRef: memberRef,
          callsign: callsign,
          gameId: gameId,
          officialRankName: officialRankName,
          officialRankValue: officialRankValue,
          presence: value,
          server: server,
          ship: ship,
          location: location,
          starBridgeConnected: starBridgeConnected,
          avatarUrl: avatarUrl,
          identityState: identityState,
          avatarImageData: avatarImageData,
          profileTargetRef: profileTargetRef,
          arrivalPending: arrivalPending,
          sharingPaused: sharingPaused,
          isSelf: isSelf,
          serverRegion: serverRegion,
          hasServerSession: hasServerSession,
          locationHiddenReason: locationHiddenReason,
          arrivalTargetCode: arrivalTargetCode,
        );

  bool sameValue(OfficialFleetMember other) =>
      (
        memberRef,
        callsign,
        gameId,
        avatarUrl,
        identityState,
        avatarImageData,
        profileTargetRef,
        officialRankName,
        officialRankValue,
        presence,
        starBridgeConnected,
        arrivalPending,
        sharingPaused,
        isSelf,
        serverRegion,
        hasServerSession,
        locationHiddenReason,
        arrivalTargetCode,
        server.state,
        server.value,
        ship.state,
        ship.value,
        location.state,
        location.value,
      ) ==
      (
        other.memberRef,
        other.callsign,
        other.gameId,
        other.avatarUrl,
        other.identityState,
        other.avatarImageData,
        other.profileTargetRef,
        other.officialRankName,
        other.officialRankValue,
        other.presence,
        other.starBridgeConnected,
        other.arrivalPending,
        other.sharingPaused,
        other.isSelf,
        other.serverRegion,
        other.hasServerSession,
        other.locationHiddenReason,
        other.arrivalTargetCode,
        other.server.state,
        other.server.value,
        other.ship.state,
        other.ship.value,
        other.location.state,
        other.location.value,
      );

  /// A visitor must not learn hidden presence or infer it from account linkage.
  OfficialFleetMemberPresence get publicPresence {
    if (identityState != OfficialFleetMemberIdentityState.starBridge ||
        starBridgeConnected != true) {
      return OfficialFleetMemberPresence.unknown;
    }
    if (sharingPaused || presence == OfficialFleetMemberPresence.invisible) {
      return OfficialFleetMemberPresence.offline;
    }
    return presence == OfficialFleetMemberPresence.notConnected
        ? OfficialFleetMemberPresence.unknown
        : presence;
  }

  OfficialFleetMemberField get publicServer => _publicField(server);
  OfficialFleetMemberField get publicShip => _publicField(ship);
  OfficialFleetMemberField get publicLocation => _publicField(location);
  bool get publicArrivalPending =>
      publicPresence == OfficialFleetMemberPresence.inGame && arrivalPending;

  OfficialFleetMemberField _publicField(OfficialFleetMemberField field) =>
      switch (publicPresence) {
        OfficialFleetMemberPresence.inGame => field,
        OfficialFleetMemberPresence.unknown => const OfficialFleetMemberField(
          OfficialFleetMemberFieldState.unknown,
        ),
        _ => const OfficialFleetMemberField(
          OfficialFleetMemberFieldState.notInGame,
        ),
      };
}

@immutable
final class OfficialFleetMemberDirectoryQuery {
  static const maxSearchLength = 128;
  // Match the Host's UTF-16 length and char.IsControl admission boundary.
  static bool isValidSearch(String value) =>
      value.length <= maxSearchLength &&
      !RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(value);

  const OfficialFleetMemberDirectoryQuery({
    required this.sourceRef,
    this.search = '',
    this.filter = OfficialFleetMemberFilter.all,
    this.pageNumber = 1,
    this.pageSize = 50,
  }) : assert(pageNumber > 0),
       assert(pageSize == 25 || pageSize == 50 || pageSize == 100);

  final String sourceRef;
  final String search;
  final OfficialFleetMemberFilter filter;
  final int pageNumber;
  final int pageSize;

  OfficialFleetMemberDirectoryQuery copyWith({
    String? search,
    OfficialFleetMemberFilter? filter,
    int? pageNumber,
    int? pageSize,
  }) => OfficialFleetMemberDirectoryQuery(
    sourceRef: sourceRef,
    search: search ?? this.search,
    filter: filter ?? this.filter,
    pageNumber: pageNumber ?? this.pageNumber,
    pageSize: pageSize ?? this.pageSize,
  );
}

@immutable
final class OfficialFleetMemberDirectorySnapshot {
  const OfficialFleetMemberDirectorySnapshot.available({
    required this.query,
    required this.members,
    required this.totalCount,
    required this.onlineCount,
    required this.inGameCount,
    required this.totalPages,
    this.coverage = OfficialFleetRosterCoverage.unknown,
    this.supportedFilters = const {OfficialFleetMemberFilter.all},
    this.runtimeCapabilities =
        const OfficialFleetMemberRuntimeCapabilities.none(),
  }) : availability = OfficialFleetMemberDirectoryAvailability.available,
       transientFailure = false,
       failureKey = null;

  const OfficialFleetMemberDirectorySnapshot.unavailable({
    required this.query,
    required this.failureKey,
    this.transientFailure = false,
  }) : availability = OfficialFleetMemberDirectoryAvailability.unavailable,
       members = const [],
       totalCount = null,
       onlineCount = null,
       inGameCount = null,
       totalPages = null,
       coverage = OfficialFleetRosterCoverage.unknown,
       runtimeCapabilities =
           const OfficialFleetMemberRuntimeCapabilities.none(),
       supportedFilters = const {OfficialFleetMemberFilter.all};

  final OfficialFleetMemberDirectoryAvailability availability;
  final bool transientFailure;
  final OfficialFleetMemberDirectoryQuery query;
  final List<OfficialFleetMember> members;
  final int? totalCount;
  final int? onlineCount;
  final int? inGameCount;
  final int? totalPages;
  final OfficialFleetRosterCoverage coverage;
  final OfficialFleetMemberRuntimeCapabilities runtimeCapabilities;
  final Set<OfficialFleetMemberFilter> supportedFilters;
  final String? failureKey;
}

@immutable
final class OfficialFleetMemberDirectoryProjection {
  const OfficialFleetMemberDirectoryProjection.idle()
    : availability = OfficialFleetMemberDirectoryAvailability.idle,
      lastReadAtUtc = null,
      isRefreshing = false,
      query = null,
      members = const [],
      totalCount = null,
      onlineCount = null,
      inGameCount = null,
      totalPages = null,
      coverage = OfficialFleetRosterCoverage.unknown,
      runtimeCapabilities = const OfficialFleetMemberRuntimeCapabilities.none(),
      supportedFilters = const {OfficialFleetMemberFilter.all},
      failureKey = null,
      presenceWasShown = false;

  const OfficialFleetMemberDirectoryProjection.loading(
    this.query, {
    this.presenceWasShown = false,
  }) : availability = OfficialFleetMemberDirectoryAvailability.loading,
      lastReadAtUtc = null,
      isRefreshing = false,
      members = const [],
      totalCount = null,
      onlineCount = null,
      inGameCount = null,
      totalPages = null,
      coverage = OfficialFleetRosterCoverage.unknown,
      runtimeCapabilities = const OfficialFleetMemberRuntimeCapabilities.none(),
      supportedFilters = const {OfficialFleetMemberFilter.all},
      failureKey = null;

  OfficialFleetMemberDirectoryProjection.fromSnapshot(
    OfficialFleetMemberDirectorySnapshot snapshot, {
    this.lastReadAtUtc,
    List<OfficialFleetMember>? projectedMembers,
    this.presenceWasShown = false,
  }) : availability = snapshot.availability,
       isRefreshing = false,
       query = snapshot.query,
       members = List.unmodifiable(projectedMembers ?? snapshot.members),
       totalCount = snapshot.totalCount,
       onlineCount = snapshot.runtimeCapabilities.onlineCount
           ? snapshot.onlineCount
           : null,
       inGameCount = snapshot.runtimeCapabilities.inGameCount
           ? snapshot.inGameCount
           : null,
       totalPages = snapshot.totalPages,
       coverage = snapshot.coverage,
       runtimeCapabilities = snapshot.runtimeCapabilities,
       supportedFilters = Set.unmodifiable(
         snapshot.supportedFilters.where(
           (filter) =>
               filter == OfficialFleetMemberFilter.all ||
               snapshot.runtimeCapabilities.presence,
         ),
       ),
       failureKey = snapshot.failureKey;

  OfficialFleetMemberDirectoryProjection.refreshing(
    OfficialFleetMemberDirectoryProjection value,
  ) : this.retained(value, failureKey: value.failureKey, isRefreshing: true);

  OfficialFleetMemberDirectoryProjection.retained(
    OfficialFleetMemberDirectoryProjection value, {
    required this.failureKey,
    this.isRefreshing = false,
  }) : availability = value.availability,
       lastReadAtUtc = value.lastReadAtUtc,
       query = value.query,
       members = value.members,
       totalCount = value.totalCount,
       onlineCount = value.onlineCount,
       inGameCount = value.inGameCount,
       totalPages = value.totalPages,
       coverage = value.coverage,
       runtimeCapabilities = value.runtimeCapabilities,
       supportedFilters = value.supportedFilters,
       presenceWasShown = value.presenceWasShown;

  final OfficialFleetMemberDirectoryAvailability availability;

  /// Presence has been on screen since this page opened.
  final bool presenceWasShown;

  /// No rows now, but there were: the page keeps its layout for them. Holds no
  /// former name, avatar or count, only the fact that the place was in use.
  bool get presenceHeld =>
      presenceWasShown &&
      (availability != OfficialFleetMemberDirectoryAvailability.available ||
          !runtimeCapabilities.presence);
  final bool isRefreshing;
  final DateTime? lastReadAtUtc;
  bool get refreshFailed =>
      availability == OfficialFleetMemberDirectoryAvailability.available &&
      failureKey != null;
  final OfficialFleetMemberDirectoryQuery? query;
  final List<OfficialFleetMember> members;
  final int? totalCount;
  final int? onlineCount;
  final int? inGameCount;
  final int? totalPages;
  final OfficialFleetRosterCoverage coverage;
  final OfficialFleetMemberRuntimeCapabilities runtimeCapabilities;
  final Set<OfficialFleetMemberFilter> supportedFilters;
  final String? failureKey;

  /// Counts are exact only for the complete, unfiltered directory on this page.
  /// Runtime schema 2 deliberately supplies no server-side aggregate counts.
  bool get hasCompletePage =>
      availability == OfficialFleetMemberDirectoryAvailability.available &&
      runtimeCapabilities.presence &&
      query?.search == '' &&
      query?.filter == OfficialFleetMemberFilter.all &&
      totalCount != null &&
      totalCount! <= members.length;
  int? get visibleOnlineCount => hasCompletePage
      ? members
            .where(
              (m) =>
                  m.publicPresence == OfficialFleetMemberPresence.online ||
                  m.publicPresence == OfficialFleetMemberPresence.inGame,
            )
            .length
      : null;
  int? get visibleInGameCount => hasCompletePage
      ? members
            .where(
              (m) => m.publicPresence == OfficialFleetMemberPresence.inGame,
            )
            .length
      : null;
}
