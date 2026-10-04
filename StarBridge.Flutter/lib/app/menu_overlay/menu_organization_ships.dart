import 'dart:async';

import '../../features/communities/community_ships_port.dart';
import '../../features/communities/communities_module.dart';
import '../../features/communities/community_ship_statistics.dart';
import '../../features/communities/community_workspace_port.dart';
import 'menu_fleet_summary.dart';
import 'menu_organization_avatars.dart';
import 'menu_organization_presentation.dart';

/// Owns only organization ship read/projection; account authority stays in session.
final class MenuOrganizationShips {
  bool statisticsOpen = false;
  String? _target, _revision;
  Map<String, Object?>? _statistics;
  void clear() {
    statisticsOpen = false;
    _target = _revision = null;
    _statistics = null;
  }

  Future<
    ({
      CommunityShipsPage page,
      List<Map<String, Object?>> rows,
      List<Map<String, Object?>> presentation,
      Map<String, Object?>? statistics,
      String notice,
    })
  >
  read(
    CommunityShipsPort port,
    CommunityWorkspacePort media,
    MenuOrganizationAvatars avatars,
    String target,
    int offset,
    String query,
    void Function() checkCurrent,
  ) async {
    if (_target != null && _target != target) clear();
    _target = target;
    final page = await port.readShips(
      target,
      offset: offset,
      query: CommunityShipQuery(text: query),
    );
    checkCurrent();
    if (page.targetRef != target) throw StateError('retired');
    final owners = [
      for (final ship in page.ships)
        CommunityWorkspaceMember.parse({
          'memberRef': ship.ownerMemberRef,
          'gameName': ship.ownerGameName,
          'callsign': ship.ownerCallsign,
          'roleTitle': '',
          'roleColor': '#FFFFFF',
          'isSelf': ship.ownerIsSelf,
          'isOwner': false,
          'online': ship.ownerOnline,
          'hasAvatar': ship.ownerHasAvatar,
          'avatarVersion': ship.ownerAvatarVersion,
          'liveStatus': ship.ownerLiveStatus,
          'arrivalPendingConfirmation': false,
        }),
    ];
    final photos = await Future.wait(
      owners.map((owner) => avatars.read(media, target, owner)),
    );
    checkCurrent();
    var notice = '';
    if (statisticsOpen && (_statistics == null || _revision != page.revision)) {
      _statistics = null;
      try {
        final stats = await readCommunityShipStatistics(
          port,
          target,
          'zh-CN',
          checkCurrent: checkCurrent,
          firstPage: page,
        );
        checkCurrent();
        _statistics = MenuFleetSummary.project(stats);
        _revision = page.revision;
      } on Object catch (error) {
        checkCurrent();
        if (!(error is TimeoutException ||
            error is CommunityFailure &&
                const {
                  'unavailable',
                  'shipsChanged',
                  'statisticsUnavailable',
                  'dataInvalid',
                }.contains(error.code))) {
          rethrow;
        }
        statisticsOpen = false;
        notice = '暂时无法读取完整舰队统计，请重试。';
      }
    }
    return (
      page: page,
      rows: [
        for (final ship in page.ships)
          {
            'title': ship.displayName,
            'detail': ship.englishName ?? ship.manufacturer ?? '',
          },
      ],
      presentation: [
        for (final (i, ship) in page.ships.indexed)
          avatars.bind(
            {...organizationShipPresentation(ship), 'avatar': photos[i]},
            target,
            owners[i],
          ),
      ],
      statistics: statisticsOpen ? _statistics : null,
      notice: notice,
    );
  }
}
