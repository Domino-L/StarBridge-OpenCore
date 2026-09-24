import 'official_fleet_members_models.dart';
import 'official_fleet_members_port.dart';

final class InMemoryOfficialFleetMembersAdapter
    implements OfficialFleetMembersPort {
  const InMemoryOfficialFleetMembersAdapter(this._members);

  factory InMemoryOfficialFleetMembersAdapter.forReview() =>
      const InMemoryOfficialFleetMembersAdapter(_reviewMembers);

  final List<OfficialFleetMember> _members;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    final normalizedSearch = query.search.toLowerCase();
    final filtered =
        _members.where((member) {
          final matchesSearch =
              normalizedSearch.isEmpty ||
              member.callsign.toLowerCase().contains(normalizedSearch) ||
              member.gameId.toLowerCase().contains(normalizedSearch) ||
              (member.officialRankName ?? '').toLowerCase().contains(
                normalizedSearch,
              );
          final matchesFilter = switch (query.filter) {
            OfficialFleetMemberFilter.all => true,
            OfficialFleetMemberFilter.online =>
              member.presence == OfficialFleetMemberPresence.online ||
                  member.presence == OfficialFleetMemberPresence.inGame,
            OfficialFleetMemberFilter.inGame =>
              member.presence == OfficialFleetMemberPresence.inGame,
          };
          return matchesSearch && matchesFilter;
        }).toList()..sort((left, right) {
          final callsign = left.callsign.compareTo(right.callsign);
          return callsign != 0
              ? callsign
              : left.memberRef.compareTo(right.memberRef);
        });
    final start = (query.pageNumber - 1) * query.pageSize;
    final pageMembers = start >= filtered.length
        ? const <OfficialFleetMember>[]
        : filtered.sublist(
            start,
            (start + query.pageSize).clamp(0, filtered.length),
          );
    final totalPages = filtered.isEmpty
        ? 1
        : ((filtered.length + query.pageSize - 1) ~/ query.pageSize);
    return OfficialFleetMemberDirectorySnapshot.available(
      query: query,
      members: pageMembers,
      totalCount: filtered.length,
      onlineCount: _members
          .where(
            (member) =>
                member.presence == OfficialFleetMemberPresence.online ||
                member.presence == OfficialFleetMemberPresence.inGame,
          )
          .length,
      inGameCount: _members
          .where(
            (member) => member.presence == OfficialFleetMemberPresence.inGame,
          )
          .length,
      totalPages: totalPages,
      coverage: OfficialFleetRosterCoverage.completeOfficialRoster,
      supportedFilters: OfficialFleetMemberFilter.values.toSet(),
    );
  }

  @override
  Future<void> close() async {}
}

const _reviewMembers = <OfficialFleetMember>[
  OfficialFleetMember(
    memberRef: 'rsi:domino-cn',
    callsign: '多米诺',
    gameId: 'domino_CN',
    officialRankName: 'Master',
    officialRankValue: 5,
    presence: OfficialFleetMemberPresence.inGame,
    server: OfficialFleetMemberField.value('亚洲 · 同服务器'),
    ship: OfficialFleetMemberField.value('克拉克'),
    location: OfficialFleetMemberField.value('新巴贝奇'),
    starBridgeConnected: true,
  ),
  OfficialFleetMember(
    memberRef: 'rsi:aurora-2800',
    callsign: '曙光',
    gameId: 'Citizen-2800',
    officialRankName: 'Officer',
    officialRankValue: 4,
    presence: OfficialFleetMemberPresence.online,
    server: OfficialFleetMemberField(OfficialFleetMemberFieldState.notInGame),
    ship: OfficialFleetMemberField(OfficialFleetMemberFieldState.notInGame),
    location: OfficialFleetMemberField(OfficialFleetMemberFieldState.notInGame),
    starBridgeConnected: true,
  ),
  OfficialFleetMember(
    memberRef: 'rsi:polaris-2801',
    callsign: '北辰',
    gameId: 'Citizen-2801',
    officialRankName: 'Member',
    officialRankValue: 1,
    presence: OfficialFleetMemberPresence.offline,
    server: OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
    ship: OfficialFleetMemberField(OfficialFleetMemberFieldState.notShared),
    location: OfficialFleetMemberField(OfficialFleetMemberFieldState.notShared),
    starBridgeConnected: true,
  ),
  OfficialFleetMember(
    memberRef: 'rsi:voyager-2802',
    callsign: '远航者',
    gameId: 'Citizen-2802',
    officialRankName: 'Member',
    officialRankValue: 1,
    presence: OfficialFleetMemberPresence.inGame,
    server: OfficialFleetMemberField.value('欧洲'),
    ship: OfficialFleetMemberField.value('秃鹫'),
    location: OfficialFleetMemberField.value('赫斯顿近地轨道'),
    starBridgeConnected: true,
    arrivalPending: true,
  ),
  OfficialFleetMember(
    memberRef: 'rsi:watcher-2803',
    callsign: '星港守望',
    gameId: 'Citizen-2803',
    officialRankName: 'Member',
    officialRankValue: 1,
    presence: OfficialFleetMemberPresence.notConnected,
    server: OfficialFleetMemberField(
      OfficialFleetMemberFieldState.notConnected,
    ),
    ship: OfficialFleetMemberField(OfficialFleetMemberFieldState.notConnected),
    location: OfficialFleetMemberField(
      OfficialFleetMemberFieldState.notConnected,
    ),
    starBridgeConnected: false,
  ),
];
