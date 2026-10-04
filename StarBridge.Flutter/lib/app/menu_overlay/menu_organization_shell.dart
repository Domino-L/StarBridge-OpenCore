import 'dart:async';

import '../../features/communities/communities_module.dart';
import '../../features/communities/community_workspace_port.dart';
import 'menu_organization_presentation.dart';
import 'menu_feature_session.dart';
import '../../features/communities/community_overview_reader.dart';

bool sameMenuOrganization(CommunityCard a, CommunityCard b) =>
    a.organizationRef != null &&
    a.organizationRef == b.organizationRef &&
    const ['member', 'owner'].contains(a.relationship) &&
    const ['member', 'owner'].contains(b.relationship);

CommunityCard? currentMenuOrganization(
  List<CommunityCard> cards,
  CommunityCard previous,
) {
  final matches = cards.where(
    (c) =>
        sameMenuOrganization(previous, c) ||
        c.targetRef == previous.targetRef &&
            c.organizationRef == previous.organizationRef,
  );
  return matches.length == 1 ? matches.single : null;
}

/// Current authorized organization chrome, independent of the selected section.
/// No persisted permissions: invalidation clears everything; reads still check
/// membership, and retained loading frames contain no executable old commands.
final class MenuOrganizationShell {
  CommunityOverviewReader? overview;
  String? _organizationKey;
  String? _target;
  int _revision = 0;
  Map<String, Object?> _header = {};
  Map<String, Object?>? _view;
  // One display snapshot per section, scoped to the current organization.
  // These are not permission or command caches and never cross invalidation.
  final _sections = <String, Map<String, Object?>>{};
  List<CommunityCard> _cards = const [];
  DateTime? _overviewReadAt;
  int _overviewRequest = 0;
  bool _overviewPending = false;
  bool sectionTransition = false, reusingDirectory = false;

  void rebind(String old, CommunityCard card) {
    if (_target != old ||
        _organizationKey == null ||
        _organizationKey != card.organizationRef ||
        !const ['member', 'owner'].contains(card.relationship)) {
      return;
    }
    _target = card.targetRef;
    _overviewRequest++;
    _overviewPending = false;
  }

  Future<List<CommunityCard>> readCards(
    Future<CommunityDirectory> Function(String?) read,
    void Function() requireCurrent,
  ) async {
    reusingDirectory = sectionTransition && _cards.isNotEmpty;
    sectionTransition = false;
    if (!reusingDirectory) {
      _cards = await readOrganizationNavigationCards(read, requireCurrent);
    }
    requireCurrent();
    return _cards;
  }

  Map<String, Object?> project(
    String target,
    CommunityWorkspace? workspace,
    CommunityCard? card,
  ) {
    if (_target != target) {
      _target = target;
      _revision++;
      _header = {};
      _view = null;
      _sections.clear();
      _organizationKey = card?.organizationRef;
      _overviewReadAt = null;
      _overviewPending = false;
      _overviewRequest++;
    }
    if (card != null) _organizationKey = card.organizationRef;
    workspace ??= _organizationKey == null
        ? null
        : overview?.peek(_organizationKey!);
    if (workspace != null) {
      if (workspace.query.isEmpty && workspace.offset == 0) {
        _overviewReadAt = DateTime.now();
        _overviewPending = false;
        _overviewRequest++;
      }
      _header = {
        ..._header,
        'code': workspace.code,
        'description': workspace.description,
        'activeTime': workspace.activeTime,
        if (workspace.query.isEmpty && workspace.offset == 0)
          'overview': {
            'online': workspace.members.where((m) => m.online).length,
            'gaming': workspace.members
                .where(
                  (m) => m.online && m.liveStatus.toLowerCase() == 'ingame',
                )
                .length,
            'total': workspace.totalCount,
            'scoped': workspace.members.length != workspace.totalCount,
          },
      };
    }
    return {
      'identity': 'o$_revision',
      'description': card?.description ?? '',
      'activeTime': card?.activeTime ?? '',
      'overview': {'total': card?.memberCount},
      ..._header,
    };
  }

  void remember(String target, Map<String, Object?> view) {
    if (_target == target) _view = view;
  }

  void observe(
    Map<String, Object?> view, [
    Object? source,
    MenuFeatureSession? session,
  ]) {
    final org = view['organization'];
    if (org is Map &&
        org['identity'] == 'o$_revision' &&
        view['state'] == 'ready' &&
        view['busy'] != true &&
        view['refreshing'] != true &&
        view['retainedRead'] != true &&
        org['bodyLoading'] != true) {
      _view = view;
      if (org['bodyError'] != true && org['tab'] is String) {
        _sections[org['tab'] as String] = view;
      }
      if (source is CommunityWorkspacePort && session != null) {
        unawaited(
          _readOverview(source, () => session.currentView, (next) {
            if (session.visible && !session.disposed) session.emit(next);
          }),
        );
      }
    }
  }

  Future<void> _readOverview(
    CommunityWorkspacePort port,
    Map<String, Object?> Function() currentView,
    void Function(Map<String, Object?>) publish,
  ) async {
    final target = _target;
    final key = _organizationKey;
    if (overview != null && key == null) return;
    if (target == null ||
        _overviewPending ||
        (_overviewReadAt != null &&
            DateTime.now().difference(_overviewReadAt!) <
                const Duration(seconds: 15))) {
      return;
    }
    _overviewPending = true;
    _overviewReadAt = DateTime.now();
    final request = ++_overviewRequest;
    final revision = _revision;
    bool current() =>
        request == _overviewRequest &&
        revision == _revision &&
        target == _target;
    try {
      // Production uses the main client's shared preloader. The local port is
      // only for standalone/test compositions without that application owner.
      final workspace =
          await (overview != null
                  ? overview!.read(key!)
                  : port.readWorkspace(target, '', 0))
              .timeout(const Duration(seconds: 8));
      if (!current()) return;
      if (workspace == null) {
        _header = {};
      } else if (overview == null && workspace.targetRef != target) {
        return;
      } else {
        project(target, workspace, null);
      }
    } on Object catch (error) {
      if (!current()) return;
      if (organizationTransientRead(error)) return;
      _header = {};
    } finally {
      if (request == _overviewRequest) _overviewPending = false;
    }
    // Update only the current shell, never replay a captured page or keys.
    final shown = currentView();
    final org = shown['organization'];
    if (revision != _revision ||
        target != _target ||
        org is! Map ||
        org['identity'] != 'o$revision') {
      return;
    }
    publish({
      ...shown,
      'organization': {
        ...org,
        'overview': {'total': (org['overview'] as Map?)?['total']},
        ..._header,
      },
    });
  }

  Map<String, Object?>? loading(
    String? target,
    String tab, [
    String query = '',
    int offset = 0,
  ]) {
    if (target != _target || _view == null) return null;
    final cached = _sections[tab];
    final page = cached?['organization'] as Map?;
    if (cached != null &&
        page?['query'] == query &&
        page?['offset'] == offset) {
      final latest = _view!['organization'] as Map;
      return organizationRefreshingView({
        ...cached,
        'organization': {
          ...page!,
          // Keep the latest shell; returning to an old tab must not roll back
          // presence, directory portraits or summaries.
          for (final key in [
            'navigation',
            'logo',
            'overview',
            'code',
            'description',
            'activeTime',
          ])
            key: latest[key],
          'bodyLoading': false,
          'bodyError': false,
          'fleetStatistics': tab == latest['tab']
              ? page['fleetStatistics']
              : null,
        },
      }, const []);
    }
    final frame = organizationRefreshingView(_view!, const []);
    return {
      ...frame,
      'busy': true,
      'rows': <Object?>[],
      'chat': null,
      'organization': {
        ...frame['organization'] as Map,
        'tab': tab,
        'bodyLoading': true,
        'rows': <Object?>[],
      },
    };
  }

  Map<String, Object?>? failed(
    String? target,
    String tab, [
    String query = '',
    int offset = 0,
  ]) {
    final frame = loading(target, tab, query, offset);
    if (frame == null) return null;
    return {
      ...frame,
      'busy': false,
      'refreshing': false,
      'retainedRead': true,
      'notice': '暂时无法连接，请刷新重试。',
      'organization': {
        ...frame['organization'] as Map,
        'bodyLoading': false,
        'bodyError': (frame['organization'] as Map)['bodyLoading'] == true,
      },
    };
  }

  void clear() {
    _target = null;
    _organizationKey = null;
    _revision++;
    _view = null;
    _sections.clear();
    _header = {};
    _overviewReadAt = null;
    _overviewPending = false;
    _overviewRequest++;
    _cards = const [];
    sectionTransition = reusingDirectory = false;
  }
}
