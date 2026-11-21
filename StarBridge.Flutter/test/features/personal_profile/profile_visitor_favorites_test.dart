import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_ships.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_snapshot_wire.dart';

import '../gameplay_time/gameplay_time_test.dart' as support;
import 'profile_favorite_model_test.dart' as fixture;

const _moduleIds = ['favorite-ships', 'favorite-ships-1', 'favorite-ships-2'];
String _id(int index) => 'abcdef${index.toString().padLeft(26, '0')}';
String _name(int index) => 'Fixture Ship ${index + 1}';

Map<String, Object?> _page({
  int? missing,
  bool duplicateModel = false,
  bool withHangar = true,
  bool editable = false,
}) {
  final payload = fixture.page(
    editable: editable,
    modules: {
      for (final (module, id) in _moduleIds.indexed)
        id: [
          for (var index = module * 3; index < module * 3 + 3; index++)
            _id(index).toUpperCase(),
        ],
    },
  );
  final profile = Map<String, Object?>.from(payload['profile']! as Map);
  payload['profile'] = profile;
  final content = (profile['content']! as Map).cast<String, Object?>();
  content['favoriteShipCodes'] = [
    for (var index = 0; index < 3; index++) _id(index),
  ];
  final modules = content['modules']! as List;
  content['modules'] = [
    ...modules.reversed,
    {
      'id': PersonalProfileModuleIds.hangarSummary,
      'span': 3,
      'isVisible': true,
      'position': 9,
    },
    {
      'id': 'favorite-ships-3',
      'span': 3,
      'isVisible': false,
      'position': -1,
      'favoriteShipIds': [_id(9)],
    },
  ];
  profile['hangar'] = withHangar
      ? {
          'ships': [
            for (var index = 0; index < 10; index++)
              if (index != missing)
                {
                  'code': _id(index),
                  'displayName': _name(index),
                  'importedAt': '1970-01-01T00:00:00Z',
                  'isInventoryEntry': index != 9,
                  'presentation': {
                    'title': _name(index),
                    'catalogId':
                        'fixture-${duplicateModel && index == 4 ? 1 : index}',
                    'category': 'exploration',
                    'priceUsd': index == 9 ? 9999 : 100,
                  },
                },
          ],
        }
      : null;
  return payload;
}

Future<void> _show(
  WidgetTester tester,
  PersonalProfileSnapshot snapshot,
) async {
  await tester.pumpWidget(
    support.app(
      PersonalProfileModuleGrid(
        projection: PersonalProfileProjection.fromSnapshot(snapshot),
        visitorView: true,
        isVisitor: true,
        editing: false,
        layout: snapshot.moduleLayout,
        onLayoutChanged: (_) => fail('Visitor must not edit'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Iterable<String> _ids(PersonalProfileSnapshot snapshot) =>
    snapshot.favoriteShips.map((ship) => ship.identity.runtimeId);

void main() {
  testWidgets('A1: three modules resolve nine picks in layout order', (
    tester,
  ) async {
    final snapshot = parsePersonalProfileSnapshot(_page());
    expect(_ids(snapshot), [
      for (var index = 0; index < 9; index++) _id(index),
    ]);
    await _show(tester, snapshot);
    for (var index = 0; index < 9; index++) {
      expect(find.text(_name(index)), findsOneWidget);
    }
    expect(find.textContaining('已保留'), findsNothing);
  });

  testWidgets('A2: only the module missing one ship shows pending details', (
    tester,
  ) async {
    await _show(tester, parsePersonalProfileSnapshot(_page(missing: 4)));
    final modules = tester.widgetList<PersonalProfileFavoriteShips>(
      find.byType(PersonalProfileFavoriteShips),
    );
    expect(modules.map((module) => module.ships.length), [3, 2, 3]);
    expect(modules.map((module) => module.unresolvedCount), [0, 1, 0]);
    expect(find.textContaining('已保留 1 艘'), findsOneWidget);
    expect(find.text(_name(4)), findsNothing);
  });

  testWidgets(
    'A3: same model in two modules shows once in the earlier module',
    (tester) async {
      await _show(
        tester,
        parsePersonalProfileSnapshot(_page(duplicateModel: true)),
      );
      expect(find.text(_name(1)), findsOneWidget);
      expect(find.text(_name(4)), findsNothing);
      expect(find.textContaining('已保留'), findsNothing);
    },
  );

  testWidgets('visitor modules without picks do not repeat assigned ships', (
    tester,
  ) async {
    final payload = _page();
    final profile = payload['profile']! as Map;
    final content = profile['content']! as Map;
    final modules = content['modules']! as List;
    (modules.first as Map).remove('favoriteShipIds');
    await _show(tester, parsePersonalProfileSnapshot(payload));
    final showcases = tester.widgetList<PersonalProfileFavoriteShips>(
      find.byType(PersonalProfileFavoriteShips),
    );
    expect(showcases.map((module) => module.ships.length), [3, 3, 0]);
  });

  testWidgets('A4: absent hangar keeps overview and favorite placeholders', (
    tester,
  ) async {
    await _show(tester, parsePersonalProfileSnapshot(_page(withHangar: false)));
    expect(find.textContaining('机库资料待接入'), findsOneWidget);
    expect(find.textContaining('已保留 3 艘'), findsNWidgets(3));
  });

  test('A5: owner fixture keeps its flat lookup and original layout order', () {
    final snapshot = parsePersonalProfileSnapshot(_page(editable: true));
    expect(snapshot.allowEditing, isTrue);
    expect(_ids(snapshot), [_id(0), _id(1), _id(2)]);
    expect(
      snapshot.moduleLayout.take(3).map((item) => item.moduleId),
      _moduleIds.reversed,
    );
    expect(snapshot.hangarSummary.unresolvedFavoriteCount, 0);
    expect(snapshot.hangarSummary.estimatedValueLabel, r'$900 USD');
    // Serialized owner display from the same fixture at ab2e8fa9.
    final encoded = jsonEncode(MenuProfileView.encodeSelf(snapshot));
    expect(
      sha256.convert(utf8.encode(encoded)).toString(),
      '09de91ec002d03535c2354d7183490ff8c41dbfa2785a0ca9bae3a573ddb96e6',
    );
  });

  testWidgets('A6: visitor sees the value of inventory rows', (tester) async {
    final snapshot = parsePersonalProfileSnapshot(_page());
    expect(snapshot.hangarSummary.shipCount, 9);
    await _show(tester, snapshot);
    expect(find.byKey(const Key('profile-hangar-value-panel')), findsOneWidget);
    expect(find.text(r'$900 USD'), findsOneWidget);
  });

  for (final perModule in [false, true]) {
    test('visitor resolves the fourth pick (perModule: $perModule)', () {
      final fourthId = _id(9);
      final payload = _page();
      final profile = payload['profile']! as Map;
      final content = profile['content']! as Map;
      (content['modules']! as List).removeLast();
      if (perModule) {
        content['favoriteShowcaseExtras'] = {
          _moduleIds[1]: fourthId.toUpperCase(),
        };
      } else {
        content['favoriteShowcaseExtra'] = [fourthId.toUpperCase()];
      }
      final snapshot = parsePersonalProfileSnapshot(payload);
      expect(_ids(snapshot), contains(fourthId));
      final holder = perModule ? _moduleIds[1] : _moduleIds[0];
      expect(
        snapshot.moduleLayout
            .singleWhere((item) => item.moduleId == holder)
            .showcaseExtra,
        [fourthId.toUpperCase()],
      );
    });
  }

  group('flat favourite modules beside picking modules', () {
    Map<String, Object?> flatPage(
      List<String> flatModules,
      List<int> codes, {
      bool duplicateModel = false,
      List<String> emptyModules = const [],
      List<String> hiddenModules = const [],
      bool editable = false,
    }) {
      final payload = _page(duplicateModel: duplicateModel, editable: editable);
      final content = (payload['profile']! as Map)['content']! as Map;
      for (final module in content['modules']! as List) {
        final id = (module as Map)['id'];
        if (flatModules.contains(id)) module.remove('favoriteShipIds');
        if (emptyModules.contains(id)) module['favoriteShipIds'] = <String>[];
        if (hiddenModules.contains(id)) module['isVisible'] = false;
      }
      content['favoriteShipCodes'] = [for (final i in codes) _id(i)];
      return payload;
    }

    List<String>? idsOf(PersonalProfileSnapshot snapshot, String module) =>
        snapshot.moduleLayout
            .singleWhere((item) => item.moduleId == module)
            .favoriteShipIds
            ?.map((id) => id.toLowerCase())
            .toList();

    test('a flat module shows its flat ships next to picking modules', () {
      final snapshot = parsePersonalProfileSnapshot(
        flatPage([_moduleIds[2]], [6, 7, 8]),
      );
      expect(idsOf(snapshot, _moduleIds[2]), [_id(6), _id(7), _id(8)]);
      expect(_ids(snapshot).toSet(), {for (var i = 0; i < 9; i++) _id(i)});
    });

    test('a ship another module picked stays only in that module', () {
      final snapshot = parsePersonalProfileSnapshot(
        flatPage([_moduleIds[2]], [0, 6, 1]),
      );
      expect(idsOf(snapshot, _moduleIds[2]), [_id(6)]);
      expect(_ids(snapshot).where((id) => id == _id(0)), hasLength(1));
    });

    test('a model another module shows is skipped', () {
      // With duplicateModel, ship 4 is the same model as ship 1.
      final snapshot = parsePersonalProfileSnapshot(
        flatPage([_moduleIds[1]], [4, 3, 5], duplicateModel: true),
      );
      expect(idsOf(snapshot, _moduleIds[1]), [_id(3), _id(5)]);
      expect(_ids(snapshot), isNot(contains(_id(4))));
    });

    test('two flat modules share the flat ships without repeats', () {
      final snapshot = parsePersonalProfileSnapshot(
        flatPage([_moduleIds[1], _moduleIds[2]], [3, 4, 5, 6, 7, 8]),
      );
      final first = idsOf(snapshot, _moduleIds[1])!;
      final second = idsOf(snapshot, _moduleIds[2])!;
      expect(first.length, lessThanOrEqualTo(3));
      expect(second.length, lessThanOrEqualTo(3));
      expect(first.toSet().intersection(second.toSet()), isEmpty);
      expect({...first, ...second}, {for (var i = 3; i < 9; i++) _id(i)});
    });

    test('several flat modules share the flat ships without repeats', () {
      final snapshot = parsePersonalProfileSnapshot(
        flatPage(_moduleIds, [0, 1, 2, 3, 4]),
      );
      final shares = [for (final m in _moduleIds) idsOf(snapshot, m)!];
      final all = [for (final share in shares) ...share];
      expect(all.toSet(), {for (var i = 0; i < 5; i++) _id(i)});
      expect(all, hasLength(5), reason: 'no ship in two modules');
    });

    testWidgets('several flat modules render each ship once', (tester) async {
      await _show(
        tester,
        parsePersonalProfileSnapshot(flatPage(_moduleIds, [0, 1, 2, 3, 4])),
      );
      for (var i = 0; i < 5; i++) {
        expect(find.text(_name(i)), findsOneWidget);
      }
    });

    test('a single visible flat module keeps the flat path', () {
      final snapshot = parsePersonalProfileSnapshot(
        flatPage(
          [_moduleIds[0]],
          [0, 1, 2],
          hiddenModules: [_moduleIds[1], _moduleIds[2]],
        ),
      );
      expect(idsOf(snapshot, _moduleIds[0]), isNull);
      expect(_ids(snapshot), containsAll([_id(0), _id(1), _id(2)]));
    });

    test('hidden picks never clear a visible flat module', () {
      final snapshot = parsePersonalProfileSnapshot(
        flatPage(
          [_moduleIds[0]],
          [0, 1, 2],
          hiddenModules: [_moduleIds[1], _moduleIds[2]],
        ),
      );
      // The snapshot keeps the hidden module's own picks; they only stop
      // filtering the visible flat module's ships.
      expect(idsOf(snapshot, _moduleIds[1]), [_id(3), _id(4), _id(5)]);
      expect(_ids(snapshot), containsAll([_id(0), _id(1), _id(2)]));
    });

    test('an explicitly empty module stays empty beside a flat one', () {
      final snapshot = parsePersonalProfileSnapshot(
        flatPage(
          [_moduleIds[0]],
          [0, 1, 2],
          emptyModules: [_moduleIds[1]],
          hiddenModules: [_moduleIds[2]],
        ),
      );
      expect(idsOf(snapshot, _moduleIds[1]), isEmpty);
      expect(idsOf(snapshot, _moduleIds[0]), [_id(0), _id(1), _id(2)]);
      expect(_ids(snapshot), containsAll([_id(0), _id(1), _id(2)]));
    });

    test('ships the response can show fill flat slots first', () {
      const missing = 'ffffffffffffffffffffffffffffffff';
      final payload = flatPage([_moduleIds[1], _moduleIds[2]], []);
      final content = (payload['profile']! as Map)['content']! as Map;
      content['favoriteShipCodes'] = [missing, for (var i = 3; i < 8; i++) _id(i)];
      final snapshot = parsePersonalProfileSnapshot(payload);
      expect(idsOf(snapshot, _moduleIds[1]), [_id(3), _id(4), _id(5)]);
      expect(idsOf(snapshot, _moduleIds[2]), [_id(6), _id(7), missing]);
    });

    test('a hidden pick never takes a visible module 4th ship', () {
      // Fixture: hidden favorite-ships-3 picks ship 9; a visible module also
      // holds ship 9 as its 4th showcase ship.
      final payload = _page();
      final content = (payload['profile']! as Map)['content']! as Map;
      content['favoriteShowcaseExtras'] = {_moduleIds[1]: _id(9).toUpperCase()};
      final snapshot = parsePersonalProfileSnapshot(payload);
      expect(
        snapshot.moduleLayout
            .singleWhere((item) => item.moduleId == _moduleIds[1])
            .showcaseExtra,
        [_id(9).toUpperCase()],
      );
      expect(_ids(snapshot), contains(_id(9)));
      expect(idsOf(snapshot, 'favorite-ships-3'), [_id(9)]);
    });

    testWidgets('the owner page in the menu keeps flat modules filled', (
      tester,
    ) async {
      // The menu shows the owner's own snapshot read-only (isVisitor: true).
      // Owner data carries the hangar's own ID spelling.
      final payload = flatPage([_moduleIds[2]], [0, 1, 2], editable: true);
      final content = (payload['profile']! as Map)['content']! as Map;
      for (final module in content['modules']! as List) {
        final ids = (module as Map)['favoriteShipIds'] as List?;
        if (ids != null) {
          module['favoriteShipIds'] = [
            for (final id in ids) (id as String).toLowerCase(),
          ];
        }
      }
      final snapshot = parsePersonalProfileSnapshot(payload);
      await _show(tester, snapshot);
      // As before 104: the flat module shows the flat list next to the module
      // that picked the same ships (owner rendering is unchanged).
      for (var i = 0; i < 3; i++) {
        expect(find.text(_name(i)), findsNWidgets(2));
      }
    });

    testWidgets('the owner page in the menu keeps exact IDs and no visitor hint', (
      tester,
    ) async {
      // A case-only difference stays unmatched for the owner, as at ab2e8fa9,
      // and the visitor-only "pending" line is not added.
      final snapshot = parsePersonalProfileSnapshot(_page(editable: true));
      await _show(tester, snapshot);
      final modules = tester.widgetList<PersonalProfileFavoriteShips>(
        find.byType(PersonalProfileFavoriteShips),
      );
      expect(modules.every((m) => !m.showPartialPending), isTrue);
      expect(find.text(_name(4)), findsNothing);
    });

    test('a hidden module 4th never takes a visible module 4th', () {
      final payload = _page();
      final content = (payload['profile']! as Map)['content']! as Map;
      final modules = content['modules']! as List;
      final hidden = modules.removeLast();
      modules.insert(0, hidden);
      content['favoriteShowcaseExtras'] = {
        'favorite-ships-3': _id(9).toUpperCase(),
        _moduleIds[1]: _id(9).toUpperCase(),
      };
      final snapshot = parsePersonalProfileSnapshot(payload);
      expect(
        snapshot.moduleLayout
            .singleWhere((item) => item.moduleId == _moduleIds[1])
            .showcaseExtra,
        [_id(9).toUpperCase()],
      );
    });

    test('a hidden module 4th never joins a single flat module', () {
      // Flat A, B, C (0, 1, 2); 4th ships: hidden module D (7) listed before
      // the visible flat module's own E (8).
      final payload = flatPage(
        [_moduleIds[0]],
        [0, 1, 2],
        hiddenModules: [_moduleIds[1], _moduleIds[2]],
      );
      final content = (payload['profile']! as Map)['content']! as Map;
      content['favoriteShowcaseExtras'] = {
        _moduleIds[1]: _id(7).toUpperCase(),
        _moduleIds[0]: _id(8).toUpperCase(),
      };
      final snapshot = parsePersonalProfileSnapshot(payload);
      expect(_ids(snapshot), [_id(0), _id(1), _id(2), _id(8)]);
    });

    test('a single flat module keeps its first ship as the large card', () {
      final payload = flatPage(
        [_moduleIds[0]],
        [0, 1, 2],
        hiddenModules: [_moduleIds[1], _moduleIds[2]],
      );
      final content = (payload['profile']! as Map)['content']! as Map;
      content['favoriteShowcaseExtra'] = [_id(9).toUpperCase()];
      final snapshot = parsePersonalProfileSnapshot(payload);
      expect(_ids(snapshot).first, _id(0));
      expect(_ids(snapshot), contains(_id(9)));
    });
  });
}
