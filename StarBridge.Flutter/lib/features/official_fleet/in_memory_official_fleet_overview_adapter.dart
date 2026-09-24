import 'official_fleet_overview_models.dart';
import 'official_fleet_overview_port.dart';

final class InMemoryOfficialFleetOverviewAdapter
    implements OfficialFleetOverviewPort {
  InMemoryOfficialFleetOverviewAdapter({required this.snapshot});

  factory InMemoryOfficialFleetOverviewAdapter.forReview() =>
      InMemoryOfficialFleetOverviewAdapter(
        snapshot: OfficialFleetOverviewSnapshot.available(
          announcement: OfficialFleetOverviewAnnouncement(
            id: 'announcement-weekly-training',
            title: '本周联合训练安排',
            summary: '周六 20:00 在 Everus Harbor 集结，完成编组后进行大型舰船岗位轮换与协同训练。',
            authorLabel: '行动协调组',
            publishedAtUtc: DateTime.utc(2026, 9, 1, 12, 20),
            unread: true,
          ),
          metrics: const OfficialFleetOverviewMetrics(
            officialMemberCount: 1286,
            visibleOnlineCount: 38,
            visibleInGameCount: 17,
            sharedRequestableShipCount: 24,
          ),
          tasks: <OfficialFleetOverviewTask>[
            OfficialFleetOverviewTask(
              id: 'members',
              title: '确认 2 名新成员的协作资料',
              detail: '资料缺少常用岗位，确认后成员目录会同步更新。',
              destination: OfficialFleetOverviewTaskDestination.members,
              dueAtUtc: DateTime.utc(2026, 9, 3, 12),
            ),
            OfficialFleetOverviewTask(
              id: 'ships',
              title: '完成舰船共享选择',
              detail: '选择愿意向主舰队长期开放请求的舰船。',
              destination: OfficialFleetOverviewTaskDestination.ships,
            ),
          ],
          observedAtUtc: DateTime.utc(2026, 9, 1, 12, 30),
        ),
      );

  final OfficialFleetOverviewSnapshot snapshot;

  @override
  Stream<void> get invalidations => const Stream<void>.empty();

  @override
  Future<OfficialFleetOverviewSnapshot> read(String sourceRef) async =>
      snapshot;

  @override
  Future<void> close() async {}
}
