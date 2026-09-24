import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'communities_module.dart';
import 'community_ships_port.dart';
import 'community_workspace_port.dart';

/// Isolated demonstration data, never a fallback for an unavailable real library.
CommunityShipsPage exampleCommunityShips(
  CommunityWorkspace workspace, {
  required bool seeded,
  required int offset,
  required String? revision,
  required CommunityShipQuery query,
}) {
  const catalog = [
    (
      'carrack',
      'Carrack',
      '卡拉克',
      'large',
      'exploration',
      'flyable',
      'carrack.png',
    ),
    (
      'vulture',
      'Vulture',
      '秃鹫',
      'small',
      'industrial',
      'flyable',
      'vulture.jpg',
    ),
    (
      'f7c-m-super-hornet-mk-ii',
      'F7C-M Super Hornet Mk II',
      '超级大黄蜂 Mk II',
      'small',
      'combat',
      'flyable',
      'f7c-m-super-hornet-mk-ii.jpg',
    ),
    (
      'zeus-mk-ii-mr',
      'Zeus Mk II MR',
      '宙斯 Mk II MR',
      'medium',
      'combat',
      'concept',
      'zeus-mk-ii-mr.jpg',
    ),
  ];
  final owners = workspace.members.take(4).toList();
  final english = query.culture == 'en-US';
  String translated(String key) => english
      ? key
      : switch (key) {
          'large' => '大型',
          'medium' => '中型',
          'small' => '小型',
          'exploration' => '探索',
          'industrial' => '工业',
          'combat' => '战斗',
          'flyable' => '可飞',
          'concept' => '概念',
          _ => key,
        };
  final rows = [
    if (seeded && owners.isNotEmpty)
      for (var i = 0; i < 25; i++)
        <String, Object?>{
          'shipRef': sha256
              .convert(utf8.encode('${workspace.targetRef}:ship:$i'))
              .toString()
              .substring(0, 32),
          'code': catalog[i % catalog.length].$1,
          'displayName': english
              ? catalog[i % catalog.length].$2
              : catalog[i % catalog.length].$3,
          'ownerMemberRef': owners[i % owners.length].memberRef,
          'ownerGameName': owners[i % owners.length].gameName,
          'ownerCallsign': owners[i % owners.length].callsign,
          'ownerOnline': owners[i % owners.length].online,
          'ownerLiveStatus': owners[i % owners.length].liveStatus,
          'ownerIsSelf': owners[i % owners.length].isSelf,
          'ownerHasAvatar': false,
          'sharedAt': '2026-09-01T12:00:00Z',
          'hangarImportedAt': '2026-09-01T10:00:00Z',
          'roleCategory': catalog[i % catalog.length].$5,
          'catalogSpec': translated(catalog[i % catalog.length].$4),
          'catalogRole': translated(catalog[i % catalog.length].$5),
          'catalogIconKey':
              '${catalog[i % catalog.length].$5}-${catalog[i % catalog.length].$4}',
          'catalogStatus': translated(catalog[i % catalog.length].$6),
          // No fabricated market values, custom uploads or reports.
          'catalogPriceUsd': null,
          'catalogImageAsset':
              'assets/ships/catalog-${catalog[i % catalog.length].$7}',
          'catalogThumbnailAsset':
              'assets/ships/${catalog[i % catalog.length].$7}',
          'hasCustomImage': false,
          'customImageCropFocusX': .5,
          'customImageCropFocusY': .5,
          'customImageCropZoom': 1.0,
        },
  ];
  final found = rows.where((row) {
    final spec = row['catalogSpec'];
    final status = row['catalogStatus'];
    final matchesFilter =
        query.filter == 'all' ||
        (const {'small', 'medium', 'large', 'capital'}.contains(query.filter)
            ? spec == translated(query.filter)
            : status == translated(query.filter));
    return matchesFilter &&
        [
              row['displayName'],
              row['code'],
              row['ownerGameName'],
              row['ownerCallsign'],
              spec,
              status,
              row['catalogRole'],
              row['catalogPriceUsd'],
            ]
            .whereType<String>()
            .join(' ')
            .toLowerCase()
            .contains(query.text.toLowerCase());
  }).toList();
  final field = switch (query.sort) {
    'name' => 'displayName',
    'owner' => 'ownerCallsign',
    'spec' => 'catalogSpec',
    'role' => 'catalogRole',
    'status' => 'catalogStatus',
    _ => 'catalogPriceUsd',
  };
  int compare(Map<String, Object?> a, Map<String, Object?> b) {
    final x = a[field], y = b[field];
    if (x == null && y != null) return 1;
    if (y == null && x != null) return -1;
    var result = 0;
    if (query.sort == 'spec') {
      int rank(Object? value) => [
        translated('small'),
        translated('medium'),
        translated('large'),
        translated('capital'),
      ].indexOf(value as String);
      result = rank(x).compareTo(rank(y));
    } else {
      result = (x?.toString() ?? '').compareTo(y?.toString() ?? '');
    }
    if (query.descending) result = -result;
    return result != 0
        ? result
        : (a['shipRef'] as String).compareTo(b['shipRef'] as String);
  }

  found.sort(compare);
  final currentRevision = sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'target': workspace.targetRef,
            'query': query.toPayload(),
            'rows': rows,
          }),
        ),
      )
      .toString();
  if (revision != null && revision != currentRevision) {
    throw const CommunityFailure('shipsChanged');
  }
  if (offset < 0 || offset % 20 != 0 || offset > found.length) {
    throw const CommunityFailure('dataInvalid');
  }
  final page = found.skip(offset).take(20).toList();
  return CommunityShipsPage.parse({
    'schemaVersion': 1,
    'queryVersion': 2,
    'query': query.toPayload(),
    'targetRef': workspace.targetRef,
    'revision': currentRevision,
    'offset': offset,
    'totalCount': rows.length,
    'matchedCount': found.length,
    'next': offset + page.length < found.length ? offset + page.length : null,
    'ships': page,
  });
}
