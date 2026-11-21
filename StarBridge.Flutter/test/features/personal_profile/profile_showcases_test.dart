import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_achievement_showcase.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_edit_groups.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_showcases.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_side_rail.dart';

import '../gameplay_time/gameplay_time_test.dart' as support;

Map<String, Object?> _payload({
  required bool editable,
  Map<String, Object?> content = const {},
  Object? publicAchievements,
}) => {
  'schemaVersion': 1,
  'editable': editable,
  'profile': {
    'isPublic': true,
    'visibility': 'everyone',
    'revision': 3,
    'identity': {'callSign': 'Showcase Pilot', 'gameHandle': 'Showcase_Pilot'},
    'content': {
      'introduction': 'Hello',
      'modules': [
        {'id': 'favorite-ships', 'span': 3, 'isVisible': true, 'position': 0},
        {'id': 'hangar-summary', 'span': 3, 'isVisible': true, 'position': 3},
        {'id': 'skilled-roles', 'span': 2, 'isVisible': true, 'position': 6},
      ],
      ...content,
    },
    'publicAchievements': ?publicAchievements,
  },
};

List<String> _order(List<PersonalProfileModuleLayoutItem> layout) {
  final visible =
      PersonalProfileLayout.singleColumn(layout)
          .where((e) => e.isVisible)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
  return [for (final item in visible) item.moduleId];
}

void main() {
  test(
    'without a saved list the trading card ends; playtime is in the rail',
    () {
      final snapshot = parsePersonalProfileSnapshot(_payload(editable: true));
      final layout = PersonalProfileLayout.normalize(snapshot.moduleLayout);
      // User 11-11: the playtime showcase is retired; the side rail leads with it.
      expect(layout.where((e) => e.moduleId == 'gameplay-time'), isEmpty);
      expect(_order(layout), [
        'favorite-ships',
        'hangar-summary',
        'skilled-roles',
        'trade-card',
      ]);
      expect(
        layout.where((e) => e.moduleId == 'achievements').single.isVisible,
        isFalse,
      );
      // 11-08: the organization showcase is retired; the rail shows them.
      expect(layout.where((e) => e.moduleId == 'organizations'), isEmpty);
      // Released clients never see a showcase-only id in `modules`.
      expect(
        PersonalProfileShowcases.modulesOf(layout).map((e) => e.moduleId),
        isNot(contains('achievements')),
      );
    },
  );

  test('a saved list sets the order and the showcase-only switches', () {
    final snapshot = parsePersonalProfileSnapshot(
      _payload(
        editable: true,
        content: {
          'showcases': [
            {'id': 'achievements', 'isVisible': true},
            {'id': 'skilled-roles', 'isVisible': true},
            {'id': 'trade-card', 'isVisible': false},
            {'id': 'favorite-ships', 'isVisible': true},
            {'id': 'unknown-future', 'isVisible': true},
            {'id': 'achievements', 'isVisible': false},
          ],
          'achievementShowcase': ['journey-area18', 'first-entry', 'BAD ID'],
        },
      ),
    );
    final layout = PersonalProfileLayout.normalize(snapshot.moduleLayout);
    expect(_order(layout), [
      'achievements',
      'skilled-roles',
      'favorite-ships',
      'hangar-summary',
    ]);
    // A list saved while the playtime showcase existed is read without it.
    final placed = parsePersonalProfileSnapshot(
      _payload(
        editable: true,
        content: {
          'showcases': [
            {'id': 'hangar-summary', 'isVisible': true},
            {'id': 'favorite-ships', 'isVisible': true},
            {'id': 'skilled-roles', 'isVisible': true},
            {'id': 'gameplay-time', 'isVisible': true},
          ],
        },
      ),
    );
    expect(
      _order(PersonalProfileLayout.normalize(placed.moduleLayout)).take(3),
      ['hangar-summary', 'favorite-ships', 'skilled-roles'],
    );
    expect(
      PersonalProfileLayout.normalize(placed.moduleLayout)
          .where((e) => e.moduleId == 'gameplay-time'),
      isEmpty,
    );
    // Merging again without a list never brings it back.
    final remerged = PersonalProfileShowcases.merge(
      PersonalProfileLayout.normalize(placed.moduleLayout),
      null,
    );
    expect(remerged.where((e) => e.moduleId == 'gameplay-time'), isEmpty);
    expect(snapshot.showcaseData.achievementShowcase, [
      'journey-area18',
      'first-entry',
    ]);
    expect(snapshot.showcaseData.publicAchievements, isNull);
  });

  test('a visitor read keeps only the server public list, never picks', () {
    final valid = parsePersonalProfileSnapshot(
      _payload(
        editable: false,
        content: {
          'achievementShowcase': ['first-entry'],
        },
        publicAchievements: [
          {'id': 'journey-area18', 'earnedAt': '2026-09-21T12:00:00Z'},
        ],
      ),
    );
    expect(valid.showcaseData.achievementShowcase, isNull);
    expect(valid.showcaseData.publicAchievements!.single.id, 'journey-area18');
    for (final bad in [
      [
        {'id': 'journey-area18', 'earnedAt': '2026-09-21T12:00:00'},
      ],
      [
        {'id': 'Bad Id', 'earnedAt': '2026-09-21T12:00:00Z'},
      ],
      [
        for (var i = 0; i < 10; i++)
          {'id': 'a$i', 'earnedAt': '2026-09-21T12:00:00Z'},
      ],
    ]) {
      expect(
        parsePersonalProfileSnapshot(
          _payload(editable: false, publicAchievements: bad),
        ).showcaseData.publicAchievements,
        isNull,
      );
    }
  });

  test('edits send the showcase list and picks in the layout group only', () {
    final displayed = parsePersonalProfileSnapshot(_payload(editable: true));
    PersonalProfileEdit edit(
      List<PersonalProfileModuleLayoutItem> layout, [
      List<String>? picks,
    ]) => PersonalProfileEdit(
      callSign: displayed.callSign,
      about: displayed.about,
      avatarStyle: displayed.avatarStyle,
      wallpaperId: displayed.wallpaperId,
      visibility: displayed.visibility,
      moduleLayout: layout,
      achievementShowcase: picks,
    );
    final same = PersonalProfileLayout.normalize(displayed.moduleLayout);
    expect(personalProfileEditGroups(displayed, edit(same)), isEmpty);

    final shown = PersonalProfileLayout.show(
      PersonalProfileLayout.singleColumn(same),
      'achievements',
      requestedPosition: 15,
    ).layout;
    final groups = personalProfileEditGroups(
      displayed,
      edit(PersonalProfileLayout.singleColumn(shown), ['first-entry']),
    );
    final layoutGroup = groups['layout']!;
    expect((layoutGroup['showcases'] as List).first, {
      'id': 'favorite-ships',
      'isVisible': true,
    });
    expect(
      (layoutGroup['showcases'] as List),
      contains(equals({'id': 'achievements', 'isVisible': true})),
    );
    expect(layoutGroup['achievementShowcase'], ['first-entry']);
    for (final module in (layoutGroup['modules'] as List? ?? const [])) {
      expect(
        PersonalProfileShowcaseIds.isShowcaseOnly(
          (module as Map)['id'] as String,
        ),
        isFalse,
      );
    }
  });

  testWidgets('a visitor sees only the achievements the server allowed', (
    tester,
  ) async {
    Future<void> pump(Object? publicAchievements) async {
      final snapshot = parsePersonalProfileSnapshot(
        _payload(
          editable: false,
          content: {
            'showcases': [
              {'id': 'achievements', 'isVisible': true},
            ],
          },
          publicAchievements: publicAchievements,
        ),
      );
      final projection = PersonalProfileProjection.fromSnapshot(snapshot);
      await tester.binding.setSurfaceSize(const Size(1100, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        support.app(
          SingleChildScrollView(
            child: PersonalProfileModuleGrid(
              projection: projection,
              visitorView: true,
              isVisitor: true,
              editing: false,
              layout: PersonalProfileLayout.normalize(projection.moduleLayout),
              onLayoutChanged: (_) => fail('Visitor must not edit'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump([
      {'id': 'journey-area18', 'earnedAt': '2026-09-21T12:00:00Z'},
      {'id': 'first-entry', 'earnedAt': '2026-08-01T12:00:00Z'},
    ]);
    expect(find.byKey(const Key('profile-achievement-hero')), findsOneWidget);
    expect(
      find.byKey(const Key('profile-achievement-first-entry')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // No public list for this viewer: the showcase is left out entirely.
    await pump(null);
    expect(find.byKey(const Key('profile-module-achievements')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the owner showcase shows picks from the shared collection', (
    tester,
  ) async {
    final snapshot = parsePersonalProfileSnapshot(
      _payload(
        editable: true,
        content: {
          'showcases': [
            {'id': 'achievements', 'isVisible': true},
          ],
        },
      ),
    );
    final projection = PersonalProfileProjection.fromSnapshot(snapshot);
    final collection = ValueNotifier(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        catalog: achievementCatalog,
        earnedAt: {
          'first-entry': DateTime.utc(2026, 8, 1),
          'journey-area18': DateTime.utc(2026, 9, 21),
          'journey-lorville': DateTime.utc(2026, 9, 1),
        },
      ),
    );
    addTearDown(collection.dispose);
    await tester.binding.setSurfaceSize(const Size(1100, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      support.app(
        ProfileAchievementsScope(
          collection: collection,
          activate: () async {},
          child: SingleChildScrollView(
            child: PersonalProfileModuleGrid(
              projection: projection,
              visitorView: false,
              editing: false,
              layout: PersonalProfileLayout.normalize(projection.moduleLayout),
              achievementPicks: const ['journey-lorville', 'first-entry'],
              onLayoutChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Picks in pick order; an earned achievement not picked is left out.
    expect(
      find.byKey(const Key('profile-achievement-first-entry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-achievement-journey-area18')),
      findsNothing,
    );
    expect(find.text('已获得 3 / ${achievementCatalog.length}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // User 11-08: "我觉得组织不应该单独一个展柜，默认右侧显示就行了".
  testWidgets('a saved organization showcase is ignored; the rail shows them', (
    tester,
  ) async {
    final snapshot = parsePersonalProfileSnapshot(
      _payload(
        editable: true,
        content: {
          'showcases': [
            {'id': 'organizations', 'isVisible': true},
            {'id': 'gameplay-time', 'isVisible': true},
          ],
        },
      ),
    );
    final layout = PersonalProfileLayout.normalize(snapshot.moduleLayout);
    expect(layout.map((e) => e.moduleId), isNot(contains('organizations')));
    expect(layout.map((e) => e.moduleId), isNot(contains('gameplay-time')));
    expect(PersonalProfileShowcaseIds.isShowcaseOnly('organizations'), isFalse);
    await tester.pumpWidget(
      support.app(
        PersonalProfileSideRail(
          projection: PersonalProfileProjection.fromSnapshot(snapshot),
          isSelf: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-rail-organizations')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
