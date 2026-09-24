import 'package:flutter/foundation.dart';

enum OfficialFleetMemberDirectoryAvailability {
  idle,
  loading,
  available,
  unavailable,
}

enum OfficialFleetMemberFilter { all, online, inGame }

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
    this.arrivalPending = false,
  });

  final String memberRef;
  final String callsign;
  final String gameId;
  final String? avatarUrl;
  final String? officialRankName;
  final int? officialRankValue;
  final OfficialFleetMemberPresence presence;
  final OfficialFleetMemberField server;
  final OfficialFleetMemberField ship;
  final OfficialFleetMemberField location;
  // null means that the source has not confirmed application enrollment.
  final bool? starBridgeConnected;
  final bool arrivalPending;
}

@immutable
final class OfficialFleetMemberDirectoryQuery {
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
  }) : availability = OfficialFleetMemberDirectoryAvailability.available,
       failureKey = null;

  const OfficialFleetMemberDirectorySnapshot.unavailable({
    required this.query,
    required this.failureKey,
  }) : availability = OfficialFleetMemberDirectoryAvailability.unavailable,
       members = const [],
       totalCount = null,
       onlineCount = null,
       inGameCount = null,
       totalPages = null,
       coverage = OfficialFleetRosterCoverage.unknown,
       supportedFilters = const {OfficialFleetMemberFilter.all};

  final OfficialFleetMemberDirectoryAvailability availability;
  final OfficialFleetMemberDirectoryQuery query;
  final List<OfficialFleetMember> members;
  final int? totalCount;
  final int? onlineCount;
  final int? inGameCount;
  final int? totalPages;
  final OfficialFleetRosterCoverage coverage;
  final Set<OfficialFleetMemberFilter> supportedFilters;
  final String? failureKey;
}

@immutable
final class OfficialFleetMemberDirectoryProjection {
  const OfficialFleetMemberDirectoryProjection.idle()
    : availability = OfficialFleetMemberDirectoryAvailability.idle,
      query = null,
      members = const [],
      totalCount = null,
      onlineCount = null,
      inGameCount = null,
      totalPages = null,
      coverage = OfficialFleetRosterCoverage.unknown,
      supportedFilters = const {OfficialFleetMemberFilter.all},
      failureKey = null;

  const OfficialFleetMemberDirectoryProjection.loading(this.query)
    : availability = OfficialFleetMemberDirectoryAvailability.loading,
      members = const [],
      totalCount = null,
      onlineCount = null,
      inGameCount = null,
      totalPages = null,
      coverage = OfficialFleetRosterCoverage.unknown,
      supportedFilters = const {OfficialFleetMemberFilter.all},
      failureKey = null;

  OfficialFleetMemberDirectoryProjection.fromSnapshot(
    OfficialFleetMemberDirectorySnapshot snapshot,
  ) : availability = snapshot.availability,
      query = snapshot.query,
      members = List.unmodifiable(snapshot.members),
      totalCount = snapshot.totalCount,
      onlineCount = snapshot.onlineCount,
      inGameCount = snapshot.inGameCount,
      totalPages = snapshot.totalPages,
      coverage = snapshot.coverage,
      supportedFilters = Set.unmodifiable(snapshot.supportedFilters),
      failureKey = snapshot.failureKey;

  final OfficialFleetMemberDirectoryAvailability availability;
  final OfficialFleetMemberDirectoryQuery? query;
  final List<OfficialFleetMember> members;
  final int? totalCount;
  final int? onlineCount;
  final int? inGameCount;
  final int? totalPages;
  final OfficialFleetRosterCoverage coverage;
  final Set<OfficialFleetMemberFilter> supportedFilters;
  final String? failureKey;
}
