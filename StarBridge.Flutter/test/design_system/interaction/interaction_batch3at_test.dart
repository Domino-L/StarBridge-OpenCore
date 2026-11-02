import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_dialog.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_modules.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_controls.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import 'interaction_batch3ac_test.dart' show LiveState;
import 'interaction_batch3ae_test.dart' show mount, action;
import 'interaction_batch3aa_test.dart' show open, select;
import 'interaction_batch3ao_test.dart' show check;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;

const a = '11111111111111111111111111111111';
const b = '22222222222222222222222222222222';
const missing = '33333333333333333333333333333333';
const ships = [
  PersonalProfileShipSummary(
    identity: PersonalProfileShipIdentity(
      runtimeId: a,
      englishName: 'Carrack',
      simplifiedChineseName: '卡拉克',
      traditionalChineseName: '卡拉克',
    ),
    manufacturer: 'Anvil',
    imageAsset: '',
    roleKey: 'exploration',
    crewLabel: '',
    sizeKey: '',
    valueLabel: '',
  ),
  PersonalProfileShipSummary(
    identity: PersonalProfileShipIdentity(
      runtimeId: b,
      englishName: 'Cutlass',
      simplifiedChineseName: '弯刀',
      traditionalChineseName: '彎刀',
    ),
    manufacturer: 'Drake',
    imageAsset: '',
    roleKey: 'multi-role',
    crewLabel: '',
    sizeKey: '',
    valueLabel: '',
  ),
];
const local = PersonalProfileLocalView(
  choices: ships,
  favoriteShipIds: [],
  hangarAvailable: true,
  remoteAvailable: true,
);
const item = PersonalProfileModuleLayoutItem(
  moduleId: 'favorite-ships',
  size: PersonalProfileModuleSize.one,
  isVisible: true,
  position: 0,
  favoriteShipIds: [],
);

PersonalProfileProjection projection() => const PersonalProfileProjection(
  availability: PersonalProfileAvailability.available,
  operation: PersonalProfileOperation.none,
  callSign: 'Synthetic pilot',
  gameHandle: '',
  about: '',
  avatarStyle: 0,
  wallpaperId: 'none',
  visibility: PersonalProfileVisibility.onlyMe,
  presenceIntent: PersonalProfilePresenceIntent.none,
  affiliations: [],
  availabilityWindows: [],
  timeZoneLabel: '',
  gameplayMinutes: 0,
  activityRhythm: PersonalProfileActivityRhythm.casual,
  roles: [],
  participationInterests: [],
  supportCapabilities: [],
  shipWishlist: [],
  favoriteShips: [],
  hangarSummary: PersonalProfileHangarSummary.empty(),
  moduleLayout: [item],
  allowEditing: true,
  local: local,
);

InteractionSource origin(String source) => source == 'pointer'
    ? InteractionSource.pointer
    : InteractionSource.keyboard;

Future<void> icon(
  WidgetTester t,
  Key key,
  String source, {
  bool settle = true,
}) async {
  final target = find.byKey(key);
  await t.ensureVisible(target);
  if (source == 'keyboard') {
    final leaf = find
        .descendant(of: target, matching: find.byType(StarBridgeIcon))
        .first;
    Focus.of(t.element(leaf)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    if (settle) await settleCommunityImages(t);
  } else {
    await action(t, key, source, settle: settle);
  }
}

Finder tile(String id) => find.byWidgetPredicate(
  (w) =>
      w is StarBridgeCheckboxTile &&
      w.controlKey == Key('profile-favorite-$id'),
);
StarBridgeActionButton apply(WidgetTester t) => t.widget(
  find.byWidgetPredicate(
    (w) =>
        w is StarBridgeActionButton &&
        w.controlKey == const Key('profile-favorites-apply'),
  ),
);

class Grid extends StatefulWidget {
  const Grid({super.key, this.reserve = false});
  final bool reserve;
  @override
  State<Grid> createState() => GridState();
}

class GridState extends State<Grid> {
  var data = projection();
  late var layout = PersonalProfileLayout.normalize([
    item,
    if (widget.reserve)
      const PersonalProfileModuleLayoutItem(
        moduleId: 'favorite-ships-1',
        size: PersonalProfileModuleSize.one,
        isVisible: true,
        position: 1,
        favoriteShipIds: [b],
      ),
  ]);
  final calls = <(List<PersonalProfileModuleLayoutItem>, InteractionSource)>[];
  bool visible = true;
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => visible
      ? SingleChildScrollView(
          child: PersonalProfileModuleGrid(
            projection: data,
            visitorView: false,
            editing: true,
            layout: layout,
            onLayoutChanged: (next) {
              calls.add((next, currentStarBridgeActivationSource));
              setState(() => layout = next);
            },
          ),
        )
      : const Text('Source removed');
}

Future<(GridState, LiveState)> grid(
  WidgetTester t,
  InteractionSuite suite, {
  bool reserve = false,
  GlobalKey? capture,
}) async {
  final key = GlobalKey<GridState>();
  final live = await mount(
    t,
    Grid(key: key, reserve: reserve),
    suite,
    width: 1100,
    capture: capture,
  );
  return (key.currentState!, live);
}

Future<void> editGrid(WidgetTester t, String source, {bool settle = true}) =>
    icon(
      t,
      const Key('profile-module-edit-favorite-ships'),
      source,
      settle: settle,
    );

Future<void> capture(WidgetTester t, GlobalKey key, String name) async =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      final dir = Directory('build/reviews/interaction-batch3at');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });

void main() {
  setUpAll(loadFonts);
  testWidgets('module compact controls retain original header budget', (
    t,
  ) async {
    await mount(
      t,
      Center(
        child: PersonalProfileModuleControls(
          item: item,
          onSizeSelected: (_) {},
          onRemove: () {},
          onEditShips: () {},
        ),
      ),
      InteractionSuite.standard,
    );
    expect(
      t
          .getSize(find.byKey(const Key('profile-module-edit-favorite-ships')))
          .height,
      lessThanOrEqualTo(32),
    );
    expect(
      t
          .getSize(
            find.byKey(const Key('profile-module-remove-favorite-ships')),
          )
          .width,
      lessThanOrEqualTo(32),
    );
  });
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'module controls preserve callback authority and source $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final calls = <(String, InteractionSource)>[];
          await mount(
            t,
            Center(
              child: PersonalProfileModuleControls(
                item: item,
                onSizeSelected: (size) =>
                    calls.add((size.name, currentStarBridgeActivationSource)),
                onEditShips: () =>
                    calls.add(('ships', currentStarBridgeActivationSource)),
                onEditPositions: () =>
                    calls.add(('positions', currentStarBridgeActivationSource)),
                onRemove: () =>
                    calls.add(('remove', currentStarBridgeActivationSource)),
              ),
            ),
            suite,
          );
          const sizeKey = Key('profile-module-size-favorite-ships');
          await open(t, sizeKey, source);
          await t.pumpAndSettle();
          expect(nativeViewportMenus.value, 1);
          final entries = t
              .widget<StarBridgeMenuAnchor>(find.byType(StarBridgeMenuAnchor))
              .entries;
          expect(entries.map((e) => e.id), [
            for (final size in PersonalProfileModuleSize.values)
              ('profile-module-size-favorite-ships', size),
          ]);
          expect(entries.first.onActivate, isNull);
          await select(
            t,
            'profile-module-size-favorite-ships',
            PersonalProfileModuleSize.three,
            source,
          );
          await settleCommunityImages(t);
          expect(calls, [('three', origin(source))]);
          expect(nativeViewportMenus.value, 0);
          // This target is controlled: requesting three cells cannot change the one-cell value.
          expect(find.text('1 格'), findsOneWidget);
          await icon(
            t,
            const Key('profile-module-edit-favorite-ships'),
            source,
          );
          await icon(t, const Key('profile-positions-edit'), source);
          await icon(
            t,
            const Key('profile-module-remove-favorite-ships'),
            source,
          );
          expect(calls, [
            ('three', origin(source)),
            ('ships', origin(source)),
            ('positions', origin(source)),
            ('remove', origin(source)),
          ]);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );

      testWidgets(
        'repeatable add menu keeps IDs and hidden selections $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          var layout = PersonalProfileLayout.normalize([
            item.copyWith(isVisible: false, position: -1, favoriteShipIds: [a]),
            const PersonalProfileModuleLayoutItem(
              moduleId: 'favorite-ships-1',
              size: PersonalProfileModuleSize.one,
              isVisible: false,
              position: -1,
              favoriteShipIds: [b],
            ),
          ]);
          final calls = <InteractionSource>[];
          await mount(
            t,
            StatefulBuilder(
              builder: (_, setState) => Center(
                child: PersonalProfileAddModuleButton(
                  hiddenModuleIds: [
                    ProfileFavoriteModules.addAction,
                    for (final e in layout)
                      if (!e.isVisible) e.moduleId,
                  ],
                  onSelected: (id) {
                    expect(id, ProfileFavoriteModules.addAction);
                    calls.add(currentStarBridgeActivationSource);
                    setState(() => layout = ProfileFavoriteModules.add(layout));
                  },
                ),
              ),
            ),
            suite,
          );
          for (var count = 1; count <= 3; count++) {
            await open(t, const Key('profile-add-module-anchor'), source);
            await t.pumpAndSettle();
            final menu = t.widget<StarBridgeMenuAnchor>(
              find.byType(StarBridgeMenuAnchor),
            );
            expect(
              menu.entries.where(
                (e) =>
                    e.id ==
                    ('profile-add-module', ProfileFavoriteModules.addAction),
              ),
              hasLength(1),
            );
            expect(
              menu.entries.any(
                (e) => PersonalProfileModuleIds.isFavorite(
                  (e.id as (String, String)).$2,
                ),
              ),
              false,
            );
            await select(
              t,
              'profile-add-module',
              ProfileFavoriteModules.addAction,
              source,
            );
            await settleCommunityImages(t);
            expect(
              layout.where(
                (e) =>
                    e.isVisible &&
                    PersonalProfileModuleIds.isFavorite(e.moduleId),
              ),
              hasLength(count),
            );
            expect(ProfileFavoriteModules.selections(layout), [a, b]);
            expect(ProfileFavoriteModules.valid(layout), true);
          }
          expect(calls, List.filled(3, origin(source)));
          expect(nativeViewportMenus.value, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );

      testWidgets(
        'real favorite editor retains reservation capacity and exact result $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final (state, _) = await grid(t, suite, reserve: true);
          await editGrid(t, source, settle: false);
          final route = ModalRoute.of(
            t.element(find.byType(ProfileFavoriteDialog)),
          )!;
          expect(route, isA<StarBridgeDialogRoute<List<String>>>());
          expect(route.animation!.value, source == 'pointer' ? lessThan(1) : 1);
          await settleCommunityImages(t);
          expect(state.calls, isEmpty);
          expect(t.widget<StarBridgeCheckboxTile>(tile(b)).onChanged, isNull);
          await check(t, Key('profile-favorite-$a'), source);
          expect(t.widget<StarBridgeCheckboxTile>(tile(a)).value, true);
          expect(apply(t).onActivate, isNotNull);
          await action(t, const Key('profile-favorites-apply'), source);
          expect(state.calls, hasLength(1));
          expect(state.calls.single.$2, origin(source));
          expect(
            state.layout
                .singleWhere((e) => e.moduleId == 'favorite-ships')
                .favoriteShipIds,
            [a],
          );
          expect(
            state.layout
                .singleWhere((e) => e.moduleId == 'favorite-ships-1')
                .favoriteShipIds,
            [b],
          );
          expect(ProfileFavoriteModules.valid(state.layout), true);
          expect(find.byType(ProfileFavoriteDialog), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );
    }

    for (final close in [
      'pointer',
      'keyboard',
      'reader',
      'escape',
      'barrier',
    ]) {
      testWidgets(
        'favorite cancel never applies a changed selection $suite $close',
        (t) async {
          final semantics = t.ensureSemantics();
          final (state, _) = await grid(t, suite);
          await editGrid(t, 'pointer');
          final original = state.layout;
          await check(t, Key('profile-favorite-$a'), 'pointer');
          if (close == 'escape') {
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
            expect(find.byType(ProfileFavoriteDialog), findsNothing);
          } else if (close == 'barrier') {
            await t.tapAt(const Offset(12, 12));
            await settleCommunityImages(t);
          } else {
            await action(t, const Key('profile-favorites-cancel'), close);
          }
          expect(state.calls, isEmpty);
          expect(identical(state.layout, original), true);
          expect(find.byType(ProfileFavoriteDialog), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );
    }

    testWidgets(
      'favorite native editor and selection survive live theme suite and reduce $suite',
      (t) async {
        final (state, live) = await grid(t, suite);
        await editGrid(t, 'pointer');
        await check(t, Key('profile-favorite-$a'), 'pointer');
        final field = find.byKey(const Key('profile-favorite-search'));
        await t.enterText(field, '  anVIL  ');
        await t.pumpAndSettle();
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final editor = t.state(editable);
        final controller = t.widget<EditableText>(editable).controller;
        final route = ModalRoute.of(
          t.element(find.byType(ProfileFavoriteDialog)),
        )!;
        expect(tile(b), findsNothing);
        live.change(() {
          live.suite = InteractionSuite.glow;
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(identical(t.state(editable), editor), true);
        expect(
          identical(t.widget<EditableText>(editable).controller, controller),
          true,
        );
        expect(controller.text, '  anVIL  ');
        expect(t.widget<StarBridgeCheckboxTile>(tile(a)).value, true);
        expect(route.animation!.value, 1);
        expect(
          InteractionScope.of(t.element(find.byType(ProfileFavoriteDialog)))
              .reduceMotion,
          true,
        );
        expect(state.calls, isEmpty);
        await action(t, const Key('profile-favorites-cancel'), 'keyboard');
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'favorite live reduce finishes entrance and exit within two frames $suite',
      (t) async {
        final (state, live) = await grid(t, suite);
        await editGrid(t, 'pointer', settle: false);
        final route = ModalRoute.of(
          t.element(find.byType(ProfileFavoriteDialog)),
        )!;
        expect(route.animation!.value, lessThan(1));
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        expect(route.animation!.value, 1);
        expect(route.animation!.isAnimating, false);
        live.change(() => live.reduce = false);
        await t.pump();
        await t.pump();
        await action(
          t,
          const Key('profile-favorites-cancel'),
          'pointer',
          settle: false,
        );
        expect(route.animation!.status, AnimationStatus.reverse);
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        expect(find.byType(ProfileFavoriteDialog), findsNothing);
        expect(state.calls, isEmpty);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'favorite missing and over-capacity values are removable not silently lost $suite',
      (t) async {
        await mount(
          t,
          ProfileFavoriteDialog(
            local: local,
            selected: [missing, a],
            capacity: 1,
            reserved: const {b},
          ),
          suite,
        );
        expect(apply(t).onActivate, isNull);
        expect(t.widget<StarBridgeCheckboxTile>(tile(missing)).value, true);
        await check(t, Key('profile-favorite-$missing'), 'pointer');
        expect(tile(missing), findsNothing);
        expect(t.widget<StarBridgeCheckboxTile>(tile(a)).value, true);
        expect(t.widget<StarBridgeCheckboxTile>(tile(b)).onChanged, isNull);
        expect(apply(t).onActivate, isNotNull);
        expect(t.takeException(), isNull);
      },
    );

    for (final invalidation in ['projection', 'leave', 'unrelated']) {
      testWidgets(
        'favorite route retires only its owner $suite $invalidation',
        (t) async {
          final (state, _) = await grid(t, suite);
          await editGrid(t, 'pointer');
          await check(t, Key('profile-favorite-$a'), 'pointer');
          final caller = t.element(find.byType(ProfileFavoriteDialog));
          if (invalidation == 'unrelated') {
            unawaited(
              showStarBridgeDialog<void>(
                caller,
                builder: (_) =>
                    const AlertDialog(title: Text('Unrelated top route')),
              ),
            );
            await t.pumpAndSettle();
          }
          state.change(() {
            if (invalidation == 'leave') {
              state.visible = false;
            } else {
              state.data = state.data.copyWith(callSign: 'Changed authority');
            }
          });
          await t.pump();
          await t.pump();
          await settleCommunityImages(t);
          expect(find.byType(ProfileFavoriteDialog), findsNothing);
          expect(state.calls, isEmpty);
          expect(
            state.layout
                .singleWhere((e) => e.moduleId == 'favorite-ships')
                .favoriteShipIds,
            isEmpty,
          );
          if (invalidation == 'unrelated') {
            expect(find.text('Unrelated top route'), findsOneWidget);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'module menu disable and removal release native viewport without command $suite',
      (t) async {
        var ids = [ProfileFavoriteModules.addAction];
        late StateSetter update;
        int calls = 0;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Center(
                child: PersonalProfileAddModuleButton(
                  hiddenModuleIds: ids,
                  onSelected: (_) => calls++,
                ),
              );
            },
          ),
          suite,
        );
        await open(t, const Key('profile-add-module-anchor'), 'pointer');
        await t.pumpAndSettle();
        expect(nativeViewportMenus.value, 1);
        update(() => ids = []);
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        expect(calls, 0);
        await t.tap(find.byType(PersonalProfileAddModuleButton));
        await t.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('module edit review retains approved floating surface $suite', (
      t,
    ) async {
      final boundary = GlobalKey();
      final (state, _) = await grid(t, suite, capture: boundary);
      await editGrid(t, 'pointer');
      await check(t, Key('profile-favorite-$a'), 'pointer');
      await capture(t, boundary, '${suite.name}-favorites');
      await action(t, const Key('profile-favorites-cancel'), 'pointer');
      final sizeKey = const Key('profile-module-size-favorite-ships');
      await open(t, sizeKey, 'pointer');
      await t.pump(const Duration(milliseconds: 80));
      await capture(t, boundary, '${suite.name}-size');
      expect(state.calls, isEmpty);
      expect(t.takeException(), isNull);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
    });
  }
}
