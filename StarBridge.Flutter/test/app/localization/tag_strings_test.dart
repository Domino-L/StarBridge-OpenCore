import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/community_tag_strings.dart';
import 'package:starbridge_flutter/app/localization/room_tag_strings.dart';
import 'package:starbridge_flutter/features/communities/legacy_community_tag_catalog.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_catalog.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_definitions.dart';

void main() {
  final roomSource = <String, String>{
    for (final row in roomGameplayDefinitions) 'rooms.tag.${row.$1}': row.$2,
    for (final row in roomContextDefinitions) 'rooms.tag.${row.$1}': row.$2,
  };
  final communitySource = <String, String>{
    for (final category in LegacyCommunityTagCatalog.categories) ...{
      'communities.tagCategory.${category.id}.name': category.name,
      'communities.tagCategory.${category.id}.description':
          category.description,
    },
    for (final tag in LegacyCommunityTagCatalog.tags) ...{
      'communities.tag.${tag.id}.name': tag.name,
      'communities.tag.${tag.id}.description': tag.description,
    },
  };

  for (final (locale, rooms, communities) in [
    (
      const Locale('zh', 'CN'),
      simplifiedRoomTagStrings,
      simplifiedCommunityTagStrings,
    ),
    (
      const Locale('zh', 'TW'),
      traditionalRoomTagStrings,
      traditionalCommunityTagStrings,
    ),
    (
      const Locale('en', 'US'),
      englishRoomTagStrings,
      englishCommunityTagStrings,
    ),
  ]) {
    test(
      '$locale has every room and community key registered in AppStrings',
      () {
        expect(rooms.keys.toSet(), roomSource.keys.toSet());
        expect(communities.keys.toSet(), communitySource.keys.toSet());
        final strings = AppStrings.resolve(locale);
        for (final entry in {...rooms, ...communities}.entries) {
          expect(entry.value.trim(), isNotEmpty, reason: entry.key);
          expect(
            entry.value,
            isNot(matches(RegExp(r'[\x00-\x1f]'))),
            reason: entry.key,
          );
          expect(strings.text(entry.key), entry.value, reason: entry.key);
        }
      },
    );
  }

  test('simplified display text exactly matches immutable parity catalogs', () {
    expect(simplifiedRoomTagStrings, roomSource);
    expect(simplifiedCommunityTagStrings, communitySource);
  });

  test(
    'traditional display uses traditional ship, mining and combat terms',
    () {
      final strings = AppStrings.resolve(const Locale('zh', 'TW'));
      expect(strings.text('rooms.tag.industry_ship_mining'), '單艦採礦');
      expect(strings.text('rooms.tag.combat'), '戰鬥');
      expect(strings.text('communities.tag.core_logistics.name'), '後勤');
    },
  );

  test('room display normalizes aliases and translates the complete path', () {
    final strings = AppStrings.resolve(const Locale('en', 'US'));
    const tag = RoomTag(id: 'pve_ground_combat', text: '旧名称', isGameplay: true);
    expect(
      RoomTagCatalog.fullText(tag, strings: strings),
      'Combat / PVE / Bunker clearance',
    );
    expect(
      RoomTagCatalog.compactText(tag, strings: strings),
      'Combat · PVE · Bunker clearance',
    );
    expect(
      RoomTagCatalog([]).label(tag.id, strings: strings),
      'Bunker clearance',
    );
    expect(RoomTagCatalog.fullText(tag), '战斗 / PVE / 地堡清剿');
    expect(tag.text, '旧名称');
  });

  test(
    'room context translates by ID; unknown text and separators survive',
    () {
      final strings = AppStrings.resolve(const Locale('en', 'US'));
      const context = RoomTag(id: 'need_medic', text: '缺医疗', isGameplay: false);
      const unknown = RoomTag(id: 'future', text: '原名 / 未知', isGameplay: false);
      const unknownGameplay = RoomTag(
        id: 'future_gameplay',
        text: '原玩法',
        isGameplay: true,
      );
      expect(
        RoomTagCatalog.fullText(context, strings: strings),
        'Medic needed',
      );
      expect(RoomTagCatalog.fullText(unknown, strings: strings), unknown.text);
      expect(
        RoomTagCatalog.compactText(unknown, strings: strings),
        unknown.text,
      );
      expect(
        RoomTagCatalog.fullText(unknownGameplay, strings: strings),
        unknownGameplay.text,
      );
      expect(
        RoomTagCatalog([unknown]).label('future', strings: strings),
        unknown.text,
      );
    },
  );
}
