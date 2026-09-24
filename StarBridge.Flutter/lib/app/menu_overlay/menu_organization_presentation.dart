import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_ships_port.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'menu_organization_view.dart';

Map<String, Object?> organizationRefreshingView(
  Map<String, Object?> source,
  List<Map<String, Object?>> channels,
) => {
  ...source,
  'state': 'ready',
  'busy': false,
  'channels': channels,
  'buttons': <Map<String, Object?>>[],
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
};
