import 'dart:async';

import '../../features/communities/communities_module.dart';
import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_ships_port.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'menu_organization_view.dart';

List<Map<String, Object?>> organizationChannelRows(
  List<CommunityCard> cards,
  Map<String, String?> logos,
  String? selected,
  Map<String, Object?> Function(CommunityCard) action,
) => [
  for (final item in cards)
    {
      'title': item.name,
      'avatar': logos[item.targetRef],
      'detail': selected == item.targetRef ? '当前组织频道' : '组织频道',
      'buttons': [action(item)],
    },
];

Future<List<CommunityCard>> readOrganizationNavigationCards(
  Future<CommunityDirectory> Function(String? cursor) readPage,
  void Function() requireCurrent,
) async {
  final cards = <CommunityCard>[];
  final cursors = <String>{};
  String? cursor;
  do {
    final page = await readPage(cursor);
    requireCurrent();
    cards.addAll(page.items);
    cursor = page.next;
    if (cards.length > 500 || cursor != null && !cursors.add(cursor)) {
      throw StateError('incomplete organization directory');
    }
  } while (cursor != null);
  return cards;
}

bool organizationTransientRead(Object error) =>
    error is TimeoutException ||
    error is CommunityFailure && error.code == 'unavailable';

Map<String, Object?> organizationReadFailure(Object error, String stage) {
  final label = switch (stage) {
    'workspace' => '组织资料',
    'chat' => '组织聊天',
    _ => '已加入组织列表',
  };
  final reason = error is TimeoutException
      ? '读取超时'
      : error is CommunityFailure && error.code == 'dataInvalid'
      ? '返回的数据格式不正确'
      : error is CommunityFailure && error.code == 'refreshRequired'
      ? '访问引用已过期'
      : '暂时无法读取';
  return {'state': 'unavailable', 'notice': '$label$reason，请刷新重试。'};
}

Map<String, Object?>? organizationRetainedRead(
  Map<String, Object?>? cached, {
  required bool quiet,
}) => cached == null
    ? null
    : {
        ...cached,
        'refreshing': false,
        'notice': quiet ? '' : '暂时无法连接，已保留聊天记录和草稿。',
      };

Map<String, Object?> organizationNavigationProjection(
  Map<String, Object?> view,
  List<Map<String, Object?>> navigation,
  String? logo,
) => {
  ...view,
  'organization': {
    ...view['organization'] as Map,
    'navigation': navigation,
    'logo': logo,
  },
};

Map<String, Object?>? organizationVisibleNavigation(
  Map<String, Object?> view,
  String tab,
  List<Map<String, Object?>> navigation,
  String? logo,
) {
  final shown = view['organization'];
  if (view['state'] != 'ready' || shown is! Map || shown['tab'] != tab) {
    return null;
  }
  return organizationNavigationProjection(view, navigation, logo);
}

Map<String, Object?> organizationRefreshingView(
  Map<String, Object?> source,
  List<Map<String, Object?>> channels,
) => {
  ...source,
  'state': 'ready',
  'busy': false,
  'channels': channels,
  'buttons': <Map<String, Object?>>[],
  if (source['organization'] case final Map organization)
    'organization': {
      ...organization,
      // Retain display-only section identities, never retired command keys.
      'sections': {
        if (organization['sections'] case final Map sections)
          for (final id in sections.keys) id: null,
      },
    },
  'notice': '',
  if (source['chat'] case final Map chat)
    'chat': {
      ...chat,
      'availability': 'checking',
      'receipts': <String, String>{},
    },
};

/// Bounded, presentation-only payloads; no account access or polling ownership.
Map<String, Object?> organizationPortraits(
  Map<String, Object?> view,
  String? own,
  List<CommunityChatMessage>? messages,
  Map<String, String>? photos,
) {
  final rows = view['rows'], chat = view['chat'];
  if (rows is! List || chat is! Map || chat['messages'] is! List) return view;
  final meta = chat['messages'] as List;
  final portraits = <String, String>{}, keys = <String, String>{};
  var budget = 400000;
  final updated = <Map<String, Object?>>[];
  for (var i = 0; i < rows.length; i++) {
    final isSelf = i < meta.length && (meta[i] as Map)['self'] == true;
    final String? photo = isSelf && own != null
        ? own
        : (messages != null && i < messages.length
              ? (photos?[messages[i].messageRef])
              : null);
    if (photo != null &&
        !keys.containsKey(photo) &&
        photo.length <= budget &&
        keys.length < 64) {
      final key = 'p${keys.length}';
      keys[photo] = key;
      portraits[key] = photo;
      budget -= photo.length;
    }
    updated.add({...rows[i] as Map<String, Object?>, 'portrait': keys[photo]});
  }
  return {...view, 'rows': updated, 'portraits': portraits};
}

Map<String, Object?> organizationShipPresentation(CommunitySharedShip ship) => {
  'owner': ship.ownerCallsign.isEmpty ? ship.ownerGameName : ship.ownerCallsign,
  'presence': organizationPresence(ship.ownerOnline, ship.ownerLiveStatus),
  'price': ShipCatalogDisplay.usdText(ship.catalogPriceUsd) ?? '未公布',
  'spec': ship.displaySpec,
  'role': ship.displayRole,
  'status': ship.catalogStatus,
  'image': ship.catalogThumbnailAsset ?? ship.catalogImageAsset,
  'iconKey': ship.displayIcon ?? '',
};
