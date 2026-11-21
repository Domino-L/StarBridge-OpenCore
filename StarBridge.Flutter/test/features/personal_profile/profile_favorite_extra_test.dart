import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_manufacturers.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_dialog.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_showcases.dart';

import 'local_personal_profile_test.dart' show Harness, edit;

const _a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _c = 'cccccccccccccccccccccccccccccccc';
const _d = 'dddddddddddddddddddddddddddddddd';

Map<String, Object?> _profile({
  List<String>? extra,
  bool presentation = true,
  // The second HK release always returns `mainRole`; an older server never.
  bool released = true,
  // The third HK release always returns the per-module map (user 11-06).
  Map<String, String>? perModule,
}) => {
  'schemaVersion': 3,
  'revision': 4,
  'updatedAt': '2026-11-05T00:00:00Z',
  'visibility': 'private',
  'avatarStyle': 0,
  'wallpaperId': 'none',
  'identity': {'callSign': 'Fixture', 'gameHandle': 'SyntheticPilot'},
  'content': {
    'introduction': 'Intro',
    'modules': [
      {
        'id': 'favorite-ships',
        'span': 3,
        'isVisible': true,
        'order': 0,
        'position': 0,
        'favoriteShipIds': [_a, _b, _c],
      },
      if (perModule != null)
        {
          'id': 'favorite-ships-1',
          'span': 3,
          'isVisible': true,
          'order': 1,
          'position': 1,
          'favoriteShipIds': const <String>[],
        },
    ],
    'favoriteShowcaseExtra': ?extra,
    if (released) 'mainRole': '',
    'favoriteShowcaseExtras': ?perModule,
  },
  if (presentation)
    'presentation': {
      'schemaVersion': 1,
      'sourceVersion': 'a' * 64,
      'origins': {
        for (final group in PersonalProfilePresentation.groups)
          group: 'default',
      },
    },
};

PersonalProfileSnapshot _remote(
  Map<String, Object?> profile, {
  bool editable = true,
}) => parsePersonalProfileSnapshot({
  'schemaVersion': 1,
  'editable': editable,
  'profile': profile,
});

/// A signed-in owner whose HK page presentation is (or is not) available.
Harness _harness({
  List<String>? extra,
  bool presentation = true,
  bool legacy = false,
  bool released = true,
  Map<String, String>? perModule,
}) {
  final h = Harness(legacy: legacy);
  h.session.acceptHostCapabilities([
    'account.callSign',
    'personalProfile.presentation.write.v1',
  ]);
  h.hangar.snapshot = const LocalHangarSnapshot(
    revision: 1,
    ships: [
      LocalHangarShip(id: _a, title: 'Carrack', liner: 'Anvil'),
      LocalHangarShip(id: _b, title: 'Hornet', liner: 'Anvil'),
      LocalHangarShip(id: _c, title: 'Cutlass', liner: 'Drake'),
      LocalHangarShip(id: _d, title: 'Gladius', liner: 'Aegis'),
    ],
  );
  final profile = _profile(
    extra: extra,
    presentation: presentation,
    released: released,
    perModule: perModule,
  );
  h.remote.importedSnapshot = _remote(profile);
  h.remote.presentation = presentation
      ? PersonalProfilePresentation.fromProfile(profile)
      : null;
  return h;
}

PersonalProfileModuleLayoutItem _favorites(
  Iterable<PersonalProfileModuleLayoutItem> layout,
) => layout.singleWhere((item) => item.moduleId == 'favorite-ships');

List<PersonalProfileModuleLayoutItem> _pick(
  List<PersonalProfileModuleLayoutItem> layout,
  List<String> picked,
) => [
  for (final item in layout)
    item.moduleId == 'favorite-ships'
        ? PersonalProfileFavoriteExtra.apply(item, picked)
        : item,
];

PersonalProfileEdit _edit(
  PersonalProfileSnapshot page,
  List<PersonalProfileModuleLayoutItem> layout,
) => PersonalProfileEdit(
  callSign: page.callSign,
  about: page.about,
  avatarStyle: page.avatarStyle,
  wallpaperId: page.wallpaperId,
  visibility: page.visibility,
  moduleLayout: layout,
);

Map<String, Object?> _lastLocalSave(Harness h) =>
    (h.connection.requests
                .lastWhere((r) => r.name == 'personalProfile.localSave')
                .payload['content']!
            as Map)
        .cast<String, Object?>();

void main() {
  test('the HK page holds 4: module keeps 3, the 4th goes in the extra, the '
      'local save never carries it', () async {
    final h = _harness();
    addTearDown(h.close);
    // An extra-only edit preserves the existing local picks.
    h.connection
      ..revision = 1
      ..content = {
        'favoriteShipIds': [_a, _b, _c],
      };
    final page = await h.port.read();
    final favorites = _favorites(page.moduleLayout);
    expect(favorites.showcaseExtra, isEmpty);
    expect(PersonalProfileFavoriteExtra.capacity(favorites), 4);
    final layout = _pick(page.moduleLayout, [_a, _b, _c, _d]);
    expect(_favorites(layout).favoriteShipIds, [_a, _b, _c]);
    expect(_favorites(layout).showcaseExtra, [_d]);
    expect(
      (await h.port.save(_edit(page, layout))).outcome,
      PersonalProfileActionOutcome.completed,
    );
    final group = h.remote.pageGroups!['layout']!;
    expect(group['favoriteShowcaseExtra'], [_d]);
    // The module itself did not change: only the extra is a layout edit.
    expect(group.containsKey('modules'), isFalse);
    final local = _lastLocalSave(h);
    expect(local.containsKey('favoriteShowcaseExtra'), isFalse);
    expect(local['favoriteShipIds'], [_a, _b, _c]);
    expect(jsonEncode(local), isNot(contains(_d)));
    // The full page request: only the module's 3 in `modules`.
    final request = h.remote.presentation!.editRequest(h.remote.pageGroups!)!;
    final content = request['content']! as Map;
    expect(content['favoriteShowcaseExtra'], [_d]);
    expect(
      (content['modules'] as List).single['favoriteShipIds'],
      hasLength(3),
    );
  });

  test(
    'an unchanged extra is not resent; clearing or moving it sends []',
    () async {
      final h = _harness(extra: [_d]);
      addTearDown(h.close);
      var page = await h.port.read();
      expect(_favorites(page.moduleLayout).showcaseExtra, [_d]);
      // Another edit leaves the saved extra to the server.
      await h.port.save(
        PersonalProfileEdit(
          callSign: page.callSign,
          about: 'Changed',
          avatarStyle: page.avatarStyle,
          wallpaperId: page.wallpaperId,
          visibility: page.visibility,
          moduleLayout: page.moduleLayout,
        ),
      );
      expect(h.remote.pageGroups!.containsKey('layout'), isFalse);
      expect(
        h.remote.presentation!
            .editRequest(h.remote.pageGroups!)!['content']
            .toString(),
        isNot(contains('favoriteShowcaseExtra')),
      );
      // Clearing the 4th sends an explicit [].
      page = await h.port.read();
      await h.port.save(_edit(page, _pick(page.moduleLayout, [_a, _b, _c])));
      expect(h.remote.pageGroups!['layout']!['favoriteShowcaseExtra'], isEmpty);
      expect(h.remote.pageGroups!['layout']!.containsKey('modules'), isFalse);
      // Moving the 4th into the module clears the extra: never a duplicate.
      page = await h.port.read();
      final moved = _pick(page.moduleLayout, [_a, _b, _d]);
      expect(_favorites(moved).showcaseExtra, isEmpty);
      await h.port.save(_edit(page, moved));
      final group = h.remote.pageGroups!['layout']!;
      expect(group['favoriteShowcaseExtra'], isEmpty);
      final modules = (group['modules']! as List).cast<Map>();
      expect(
        modules.singleWhere(
          (m) => m['id'] == 'favorite-ships',
        )['favoriteShipIds'],
        [_a, _b, _d],
      );
      for (final module in modules) {
        expect((module['favoriteShipIds'] as List?)?.length ?? 0, lessThan(4));
      }
      for (final save in h.connection.requests.where(
        (r) => r.name == 'personalProfile.localSave',
      )) {
        expect(
          jsonEncode(save.payload),
          isNot(contains('favoriteShowcaseExtra')),
        );
      }
    },
  );

  test(
    'without the HK page the picker keeps 3 and nothing sends the extra',
    () async {
      for (final h in [
        _harness(extra: [_d], presentation: false),
        _harness(extra: [_d], legacy: true),
      ]) {
        addTearDown(h.close);
        final page = await h.port.read();
        final favorites = _favorites(page.moduleLayout);
        expect(favorites.showcaseExtra, isNull);
        expect(PersonalProfileFavoriteExtra.capacity(favorites), 3);
        final layout = _pick(page.moduleLayout, [_a, _b, _c, _d]);
        expect(_favorites(layout).favoriteShipIds, [_a, _b, _c]);
        expect(_favorites(layout).showcaseExtra, isNull);
        await h.port.save(edit(page, callSign: page.callSign));
        expect(h.remote.writes, 0);
        expect(
          jsonEncode(_lastLocalSave(h)),
          isNot(contains('favoriteShowcaseExtra')),
        );
      }
    },
  );

  test('reads keep at most one valid id that no module already shows', () {
    for (final editable in [true, false]) {
      final layout = _remote(
        _profile(extra: ['bad', _a, _d.toUpperCase(), _c]),
        editable: editable,
      ).moduleLayout;
      expect(_favorites(layout).showcaseExtra, [_d.toUpperCase()]);
      // None saved yet: the owner may add one after the HK release only.
      expect(
        _favorites(_remote(_profile(), editable: editable).moduleLayout)
            .showcaseExtra,
        editable ? isEmpty : isNull,
      );
      expect(
        _favorites(
          _remote(_profile(released: false), editable: editable).moduleLayout,
        ).showcaseExtra,
        isNull,
      );
    }
    expect(PersonalProfileFavoriteExtra.parse('x'), isNull);
    expect(PersonalProfileFavoriteExtra.parse([_d, _c, _d]), [_d, _c]);
  });

  for (final remotePage in [true, false]) {
    testWidgets('4 ships show 1 + 3 with the maker mark on the large card '
        '(picker capacity ${remotePage ? 4 : 3})', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      LocalHangarMakerLogos.instance.debugUse({
        LocalHangarMakerLogos.asset('anvil', dark: true),
      });
      addTearDown(() => LocalHangarMakerLogos.instance.debugUse(const {}));
      final h = _harness(extra: [_d], presentation: remotePage);
      addTearDown(h.close);
      late PersonalProfileSnapshot snapshot;
      await tester.runAsync(() async => snapshot = await h.port.read());
      final projection = PersonalProfileProjection.fromSnapshot(snapshot);
      var layout = projection.moduleLayout;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark)
                .withReducedMotion(true),
            const Locale('zh', 'CN'),
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: PersonalProfileModuleGrid(
                  projection: projection,
                  visitorView: false,
                  editing: true,
                  layout: layout,
                  onLayoutChanged: (value) => setState(() => layout = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('profile-favorite-showcase')),
        findsOneWidget,
      );
      for (final id in [_a, _b, _c]) {
        expect(find.byKey(Key('profile-favorite-ship-$id')), findsOneWidget);
      }
      expect(
        find.byKey(const Key('profile-favorite-ship-$_d')),
        remotePage ? findsOneWidget : findsNothing,
      );
      // Only the large card shows the mark, and the Fan Kit notice is there.
      expect(
        find.byKey(const Key('profile-favorite-maker-$_a')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-favorite-maker-$_b')), findsNothing);
      expect(
        find.byKey(const Key('profile-favorite-fankit-notice')),
        findsOneWidget,
      );
      final control = find.byKey(
        const Key('profile-module-edit-favorite-ships'),
      );
      await tester.ensureVisible(control);
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileFavoriteDialog), findsOneWidget);
      expect(
        tester
            .widget<ProfileFavoriteDialog>(find.byType(ProfileFavoriteDialog))
            .capacity,
        remotePage ? 4 : 3,
      );
      expect(find.textContaining(remotePage ? '4/4' : '3/3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a maker without a bundled logo shows no mark and no notice', (
    tester,
  ) async {
    LocalHangarMakerLogos.instance.debugUse(const {});
    final h = _harness(extra: [_d]);
    addTearDown(h.close);
    late PersonalProfileSnapshot snapshot;
    await tester.runAsync(() async => snapshot = await h.port.read());
    final projection = PersonalProfileProjection.fromSnapshot(snapshot);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.light)
              .withReducedMotion(true),
          const Locale('zh', 'CN'),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PersonalProfileModuleGrid(
              projection: projection,
              visitorView: false,
              editing: false,
              layout: projection.moduleLayout,
              onLayoutChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-favorite-ship-$_d')), findsOneWidget);
    expect(find.byKey(const Key('profile-favorite-maker-$_a')), findsNothing);
    expect(
      find.byKey(const Key('profile-favorite-fankit-notice')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('before the second HK release the picker keeps 3 and the HK page '
      'write never carries the extra', () async {
    final h = _harness(released: false);
    addTearDown(h.close);
    final page = await h.port.read();
    final favorites = _favorites(page.moduleLayout);
    expect(favorites.showcaseExtra, isNull);
    expect(PersonalProfileFavoriteExtra.capacity(favorites), 3);
    final layout = _pick(page.moduleLayout, [_a, _b, _c, _d]);
    expect(_favorites(layout).showcaseExtra, isNull);
    await h.port.save(edit(page, callSign: page.callSign));
    expect(
      jsonEncode(h.remote.pageGroups ?? const {}),
      isNot(contains('favoriteShowcaseExtra')),
    );
  });

  // 11-06: an owner who hid the original module could never reach the 4th
  // ship; the first visible favourite module now holds the single extra.
  test('the first visible favourite module holds the 4th when the original '
      'is hidden', () {
    PersonalProfileModuleLayoutItem item(String id, bool visible, int at) =>
        PersonalProfileModuleLayoutItem(
          moduleId: id,
          size: PersonalProfileModuleSize.three,
          isVisible: visible,
          position: visible ? at : -1,
          favoriteShipIds: const [],
        );
    final layout = PersonalProfileFavoriteExtra.attach(
      [
        item('favorite-ships', false, 0),
        item('favorite-ships-2', true, 5),
        item('favorite-ships-1', true, 2),
      ],
      const [_d],
    );
    final byId = {for (final e in layout) e.moduleId: e};
    expect(PersonalProfileFavoriteExtra.capacity(byId['favorite-ships-1']!), 4);
    expect(PersonalProfileFavoriteExtra.capacity(byId['favorite-ships-2']!), 3);
    expect(PersonalProfileFavoriteExtra.capacity(byId['favorite-ships']!), 3);
    expect(PersonalProfileFavoriteExtra.of(layout), [_d]);
    // Moving another module first moves the slot with the same ship.
    final moved = PersonalProfileFavoriteExtra.attach([
      for (final e in layout)
        e.moduleId == 'favorite-ships-2'
            ? PersonalProfileModuleLayoutItem(
                moduleId: e.moduleId,
                size: e.size,
                isVisible: true,
                position: 0,
                favoriteShipIds: e.favoriteShipIds,
              )
            : e,
    ], PersonalProfileFavoriteExtra.of(layout));
    expect(
      [
        for (final e in moved)
          if (e.showcaseExtra != null) e.moduleId,
      ],
      ['favorite-ships-2'],
    );
    // No visible favourite module: the original keeps it (hidden).
    final none = PersonalProfileFavoriteExtra.attach(
      [item('favorite-ships', false, 0)],
      const [_d],
    );
    expect(none.single.showcaseExtra, [_d]);
  });
  // CX-FAV-PER-MODULE-073-R: an edit that moves or removes a favourite module
  // must move the slot at once, not after a save and a fresh read.
  testWidgets('moving or removing a favourite module moves the 4th slot '
      'during the edit', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final h = _harness(extra: [_d]);
    addTearDown(h.close);
    late PersonalProfileSnapshot snapshot;
    await tester.runAsync(() async => snapshot = await h.port.read());
    final projection = PersonalProfileProjection.fromSnapshot(snapshot);
    PersonalProfileModuleLayoutItem favourite(
      String id,
      int at,
      List<String> ships,
    ) => PersonalProfileModuleLayoutItem(
      moduleId: id,
      size: PersonalProfileModuleSize.three,
      isVisible: true,
      position: at,
      favoriteShipIds: ships,
    );
    var layout = PersonalProfileFavoriteExtra.attach(
      [
        favourite('favorite-ships', 0, const [_a]),
        favourite('favorite-ships-1', 3, const [_b]),
      ],
      const [_d],
    );
    String? holder() => [
      for (final e in layout)
        if (e.showcaseExtra != null) e.moduleId,
    ].singleOrNull;
    expect(holder(), 'favorite-ships');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark)
              .withReducedMotion(true),
          const Locale('zh', 'CN'),
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: PersonalProfileModuleGrid(
                projection: projection,
                visitorView: false,
                editing: true,
                layout: layout,
                onLayoutChanged: (value) => setState(() => layout = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('profile-module-up-favorite-ships-1')),
    );
    await tester.pumpAndSettle();
    expect(holder(), 'favorite-ships-1');
    expect(PersonalProfileFavoriteExtra.of(layout), [_d]);
    expect(
      PersonalProfileFavoriteExtra.capacity(
        layout.singleWhere((e) => e.moduleId == 'favorite-ships-1'),
      ),
      4,
    );
    await tester.tap(
      find.byKey(const Key('profile-module-remove-favorite-ships-1')),
    );
    await tester.pumpAndSettle();
    expect(holder(), 'favorite-ships');
    expect(PersonalProfileFavoriteExtra.of(layout), [_d]);
  });

  // User 11-06 "every module": the third HK release returns a 4th per module.
  test('a per-module server gives every favourite module a 4th and saves the '
      'whole map only with the layout group', () async {
    final h = _harness(perModule: const {'favorite-ships': _d});
    addTearDown(h.close);
    final page = await h.port.read();
    final byId = {for (final e in page.moduleLayout) e.moduleId: e};
    expect(PersonalProfileFavoriteExtra.capacity(byId['favorite-ships']!), 4);
    expect(PersonalProfileFavoriteExtra.capacity(byId['favorite-ships-1']!), 4);
    expect(byId['favorite-ships']!.showcaseExtra, [_d]);
    expect(byId['favorite-ships-1']!.showcaseExtra, isEmpty);
    // All four ships move to the second module: its 4th is _d; the whole
    // map is sent.
    final layout = [
      for (final e in page.moduleLayout)
        e.moduleId == 'favorite-ships'
            ? PersonalProfileFavoriteExtra.apply(e, const [])
            : e.moduleId == 'favorite-ships-1'
            ? PersonalProfileFavoriteExtra.apply(e, [_a, _b, _c, _d])
            : e,
    ];
    expect(
      (await h.port.save(_edit(page, layout))).outcome,
      PersonalProfileActionOutcome.completed,
    );
    final group = h.remote.pageGroups!['layout']!;
    expect(group['favoriteShowcaseExtras'], {'favorite-ships-1': _d});
    expect(group.containsKey('favoriteShowcaseExtra'), isFalse);
    final request = h.remote.presentation!.editRequest(h.remote.pageGroups!)!;
    expect(
      (request['content']! as Map)['favoriteShowcaseExtras'],
      group['favoriteShowcaseExtras'],
    );
    // Another group never carries the saved map.
    final intro = h.remote.presentation!.editRequest({
      'introduction': {'introduction': 'Edited'},
    })!;
    expect(
      (intro['content']! as Map).containsKey('favoriteShowcaseExtras'),
      isFalse,
    );
    expect(jsonEncode(_lastLocalSave(h)), isNot(contains(_d)));
  });

  test(
    'without the per-module map only the first visible module has a 4th',
    () async {
      final h = _harness();
      addTearDown(h.close);
      final page = await h.port.read();
      final holders = [
        for (final e in page.moduleLayout)
          if (e.showcaseExtra != null) e.moduleId,
      ];
      expect(holders, ['favorite-ships']);
    },
  );
  // CX-FAV-PER-MODULE-073-R: with a per-module server, layout edits keep each
  // module's own 4th, and a favourite module added during the edit gets one.
  testWidgets('per-module layout edits keep each module\'s 4th and give an '
      'added module its own slot', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final h = _harness(perModule: const {'favorite-ships': _d});
    addTearDown(h.close);
    late PersonalProfileSnapshot snapshot;
    await tester.runAsync(() async => snapshot = await h.port.read());
    final projection = PersonalProfileProjection.fromSnapshot(snapshot);
    expect(projection.showcaseData.favoriteExtrasEach, isTrue);
    var layout = projection.moduleLayout;
    Map<String, List<String>?> extras() => {
      for (final e in layout)
        if (e.moduleId.startsWith('favorite-ships'))
          e.moduleId: e.showcaseExtra,
    };
    expect(extras(), {
      'favorite-ships': [_d],
      'favorite-ships-1': <String>[],
    });
    final second = ([
      ...layout.where((e) => e.moduleId.startsWith('favorite-ships')),
    ]..sort((a, b) => a.position.compareTo(b.position))).last.moduleId;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark)
              .withReducedMotion(true),
          const Locale('zh', 'CN'),
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: PersonalProfileModuleGrid(
                projection: projection,
                visitorView: false,
                editing: true,
                layout: layout,
                onLayoutChanged: (value) => setState(() => layout = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('profile-module-up-$second')));
    await tester.pumpAndSettle();
    // Not the single-slot move: each module keeps its own entry.
    expect(extras(), {
      'favorite-ships': [_d],
      'favorite-ships-1': <String>[],
    });

    // A favourite module added during the edit (built without a slot).
    final added = PersonalProfileFavoriteExtra.reattach([
      ...layout,
      const PersonalProfileModuleLayoutItem(
        moduleId: 'favorite-ships-2',
        size: PersonalProfileModuleSize.three,
        isVisible: true,
        position: 9,
        favoriteShipIds: [],
      ),
    ], each: true);
    final byId = {for (final e in added) e.moduleId: e};
    expect(PersonalProfileFavoriteExtra.capacity(byId['favorite-ships-2']!), 4);
    expect(byId['favorite-ships']!.showcaseExtra, [_d]);
    // A single-slot server still keeps one slot only.
    expect([
      for (final e in PersonalProfileFavoriteExtra.reattach(added.toList()))
        if (e.showcaseExtra != null) e.moduleId,
    ], hasLength(1));
  });
}
