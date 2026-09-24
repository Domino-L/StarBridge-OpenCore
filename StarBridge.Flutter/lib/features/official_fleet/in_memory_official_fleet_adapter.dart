import 'official_fleet_models.dart';
import 'official_fleet_port.dart';

final class InMemoryOfficialFleetAdapter implements OfficialFleetPort {
  InMemoryOfficialFleetAdapter({required OfficialFleetSnapshot initial})
    : _snapshot = initial;

  factory InMemoryOfficialFleetAdapter.forReview({required bool signedIn}) {
    if (!signedIn) {
      return InMemoryOfficialFleetAdapter(
        initial: const OfficialFleetSnapshot.signedOut(),
      );
    }
    return InMemoryOfficialFleetAdapter(
      initial: OfficialFleetSnapshot.available(
        fleet: const OfficialFleetSummary(
          sourceRef: 'officialFleet:7',
          sid: 'ASTER',
          name: "Aster's Wing",
          officialRankName: 'Officer',
          officialRankValue: 4,
          profile: OfficialFleetProfileDetails(
            recruitingLabel: '正在招募',
            memberCount: 1286,
            rsiDescription:
                'Aster\'s Wing 是一支面向长期协作的综合舰队，重视清晰分工、可靠集结与成员之间的经验传承。',
            scmSupplementalDescription: '常驻亚太晚间时段，欢迎希望参与舰队行动、资源协作和多人舰船岗位训练的玩家。',
            primaryFocusLabel: '探索',
            secondaryFocusLabel: '工业',
            languageLabels: <String>['简体中文', 'English'],
            organizationModelLabel: '组织化',
            commitmentLabel: '常规投入',
            roleplayLabel: '非角色扮演',
            archetypeLabel: '综合舰队',
            tags: <String>['新手友好', '专业协作', '固定活动'],
            starBridgeRoleName: '行动协调员',
          ),
        ),
        freshness: OfficialFleetFreshness.live,
        resourceVersion: 11,
        observedAtUtc: DateTime.utc(2026, 9, 1, 12),
      ),
    );
  }

  final OfficialFleetSnapshot _snapshot;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<OfficialFleetSnapshot> read() async => _snapshot;

  @override
  Future<void> close() async {}
}
