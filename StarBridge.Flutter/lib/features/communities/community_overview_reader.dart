import 'communities_module.dart';
import 'community_workspace_port.dart';

/// Uses the main client's memberships and preloaded data, never its page state.
final class CommunityOverviewReader {
  CommunityOverviewReader(this.module);
  final CommunitiesModule module;

  CommunityCard? _member(String key) => module.overviewAvailable
      ? module.joined
            .where(
              (row) =>
                  row.organizationRef == key &&
                  const {'owner', 'member'}.contains(row.relationship),
            )
            .firstOrNull
      : null;

  CommunityWorkspace? peek(String key) {
    final card = _member(key), port = module.port;
    if (card == null || port is! CommunityWorkspacePort) return null;
    return module.workspaceSession.reads.peek(
      port as CommunityWorkspacePort,
      card.targetRef,
    );
  }

  Future<CommunityWorkspace?> read(String key) async {
    if (!module.overviewAvailable) return null;
    final revision = module.accountRevision;
    if (!module.joinedLoaded || _member(key) == null) {
      await module.refreshJoined();
    }
    if (revision != module.accountRevision || !module.overviewAvailable) {
      return null;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final card = _member(key), port = module.port;
      if (card == null || port is! CommunityWorkspacePort) return null;
      final result = await module.workspaceSession.reads.read(
        port as CommunityWorkspacePort,
        card.targetRef,
        '',
        0,
        reuseFresh: true,
      );
      if (revision != module.accountRevision ||
          !module.overviewAvailable ||
          _member(key) == null) {
        return null;
      }
      if (_member(key)!.targetRef == card.targetRef) return result;
      // Same verified membership, new transport reference. Retry through the
      // shared owner; never report a reference race as lost membership.
    }
    throw const CommunityFailure('unavailable');
  }
}
