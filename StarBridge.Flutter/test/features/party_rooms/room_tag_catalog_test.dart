import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_catalog.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_definitions.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';

void main() {
  test(
    'catalog matches every current WPF v3 node, label, parent and alias',
    () {
      final wpf = File('../shared/client-policies/PartyRoomTagCatalog.cs')
          .readAsStringSync();
      expect(wpf, contains('Version = 3'));
      final gameplay = wpf.substring(
        wpf.indexOf('GameplayRoots {'),
        wpf.indexOf('ContextGroups {'),
      );
      final stack = <String>[], rows = <(String, String, String?)>[];
      final tokens = RegExp(r'Node\("([^"]+)", "([^"]+)"|\)');
      for (final token in tokens.allMatches(gameplay)) {
        if (token.group(1) != null) {
          rows.add((token.group(1)!, token.group(2)!, stack.lastOrNull));
          stack.add(token.group(1)!);
        } else {
          stack.removeLast();
        }
      }
      expect(rows, roomGameplayDefinitions);
      expect(rows, hasLength(140));
      final contexts = wpf.substring(
        wpf.indexOf('ContextGroups {'),
        wpf.indexOf('GameplayById'),
      );
      String? group;
      final extras = <(String, String, String)>[];
      for (final token in RegExp(
        r'new\("([^"]+)", "([^"]+)"',
      ).allMatches(contexts)) {
        final id = token.group(1)!;
        if (const {'pace', 'experience', 'need'}.contains(id)) {
          group = id;
        } else {
          extras.add((id, token.group(2)!, group!));
        }
      }
      expect(extras, roomContextDefinitions);
      final aliases = {
        for (final m in RegExp(r'\["([^"]+)"\] = "([^"]+)"').allMatches(wpf))
          m.group(1)!: m.group(2)!,
      };
      expect(aliases, roomLegacyGameplayIds);
    },
  );
  test('branch replacement preserves siblings and enforces WPF limits', () {
    final catalog = RoomTagCatalog(RoomTagCatalog.exampleOptions);
    expect(catalog.adding({'combat'}, 'pve_bounty'), {'pve_bounty'});
    expect(catalog.adding({'pve_bounty'}, 'pvp_fps'), {
      'pve_bounty',
      'pvp_fps',
    });
    expect(catalog.adding({'pve_bounty', 'pvp_fps'}, 'combat'), {'combat'});
    expect(catalog.normalizeSelection({'mixed_escort'}), {
      'support_cargo_escort',
    });
    expect(catalog.invalid({}), 'required');
    expect(catalog.invalid({'combat', 'pve_bounty'}), 'branch');
    expect(
      catalog.invalid({'combat', 'industry', 'support', 'social'}),
      'gameplayLimit',
    );
    expect(
      catalog.invalid({
        'combat',
        'need_pilot',
        'need_gunner',
        'need_medic',
        'need_scout',
      }),
      'contextLimit',
    );
    expect(
      catalog.invalid({
        'combat',
        'industry',
        'social',
        'need_pilot',
        'need_gunner',
        'pace_casual',
      }),
      'totalLimit',
    );
    expect(
      catalog.invalid({
        'combat',
        'industry',
        'need_pilot',
        'need_gunner',
        'pace_casual',
      }),
      isNull,
    );
    expect(catalog.invalid({'unknown'}), 'unknown');
  });
  test('examples expose the entire catalog, filters understand ancestors and aliases', () async {
    final adapter = ExamplePartyRoomsAdapter();
    final directory = (await adapter.read()).directory!;
    expect(directory.tagOptions, hasLength(159));
    final room = directory.rooms.first;
    final leaf = RoomTagCatalog.normalize(
      room.tags.firstWhere((tag) => tag.isGameplay).id,
    );
    final parent = RoomTagCatalog.pathIds(leaf).first;
    expect(RoomTagCatalog.matches(room, {parent}, ''), isTrue);
    expect(RoomTagCatalog.matches(room, {parent, 'arena'}, ''), isTrue);
    expect(RoomTagCatalog.matches(room, {parent, 'need_scout'}, ''), isFalse);
    expect(RoomTagCatalog.matches(room, {}, 'not-a-room'), isFalse);
    expect(RoomTagCatalog.descendant(parent, leaf), isFalse);
    await adapter.close();
  });
}
