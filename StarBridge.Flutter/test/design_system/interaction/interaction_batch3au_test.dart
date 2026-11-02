import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_ships.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_hangar_overview.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/account/account_avatar_editor.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import 'interaction_batch3ac_test.dart' show LiveState;
import 'interaction_batch3ae_test.dart' show mount, action;
import 'interaction_batch3at_test.dart' show icon;
import 'interaction_batch3at_test.dart' as module_grid show Grid, GridState, a;
import 'interaction_batch3ar_test.dart' show Profile;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/personal_profile/profile_polish_regression_test.dart'
    show logo;

class PagePort implements PersonalProfilePort {
  final delegate = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  int reads = 0, writes = 0;
  @override
  Stream<void> get invalidations => delegate.invalidations;
  @override
  Future<PersonalProfileSnapshot> read() {
    reads++;
    return delegate.read();
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit value) {
    writes++;
    return delegate.save(value);
  }

  @override
  Future<void> close() => delegate.close();
}

PersonalProfileShipSummary ship(
  String id, {
  String? name,
  bool former = false,
  String? image,
  String? thumbnail,
}) => PersonalProfileShipSummary(
  identity: PersonalProfileShipIdentity(
    runtimeId: id,
    englishName: 'Carrack $id',
    simplifiedChineseName: name ?? '克拉克 $id',
    traditionalChineseName: name ?? '克拉克 $id',
  ),
  manufacturer: 'Anvil',
  imageAsset: image ?? 'assets/ships/catalog-carrack.png',
  thumbnailAsset: thumbnail ?? 'assets/ships/catalog-square-carrack.png',
  roleKey: 'profile.local.category.exploration',
  sizeKey: 'profile.shipSize.large',
  crewLabel: 'Never invent a crew fact',
  valueLabel: '\$600',
  formerlyOwned: former,
);

const summary = PersonalProfileHangarSummary(
  shipCount: 8,
  manufacturerCount: 2,
  primaryRoleKey: '',
  estimatedValueLabel: '\$1,200 USD',
  categories: [
    PersonalProfileHangarCategorySlice(
      labelKey: 'profile.local.category.combat',
      count: 5,
      category: PersonalProfileTagCategory.airCombat,
    ),
    PersonalProfileHangarCategorySlice(
      labelKey: 'profile.local.category.industrial',
      count: 3,
      category: PersonalProfileTagCategory.industry,
    ),
  ],
  recentlyAddedShip: null,
  recentlyAddedShipImageAsset: '',
  recentlyAddedAtLabel: '',
  sourceLabelKey: 'profile.local.source.hangar',
  syncedAtLabel: '2026/10/13',
  unpricedCount: 2,
);

class Shelf extends StatefulWidget {
  const Shelf({super.key, this.initial});
  final PersonalProfileShipSummary? initial;
  @override
  State<Shelf> createState() => ShelfState();
}

class ShelfState extends State<Shelf> {
  late var values = [widget.initial ?? ship('a'), ship('b')];
  bool visible = true, active = true;
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => NativeViewportScope(
    active: active,
    child: visible
        ? Center(
            child: SizedBox(
              height: 140,
              child: PersonalProfileFavoriteShips(ships: values, span: 2),
            ),
          )
        : const Text('Source removed'),
  );
}

Future<(ShelfState, LiveState, Profile)> shelf(
  WidgetTester t,
  InteractionSuite suite, {
  GlobalKey? capture,
  PersonalProfileShipSummary? initial,
}) async {
  final key = GlobalKey<ShelfState>();
  final port = Profile('Unused port');
  addTearDown(port.changes.close);
  final live = await mount(
    t,
    UserInteractionScope(
      navigation: UserPageNavigation(),
      port: port,
      messagePage: null,
      child: Shelf(key: key, initial: initial),
    ),
    suite,
    width: 1100,
    capture: capture,
  );
  return (key.currentState!, live, port);
}

Finder get detail => find.byType(Dialog);
Finder fact(String text) =>
    find.descendant(of: detail, matching: find.text(text));
Future<void> open(WidgetTester t, String source, {bool settle = true}) =>
    action(t, const Key('profile-favorite-ship-a'), source, settle: settle);
Future<void> close(WidgetTester t, String source, {bool settle = true}) =>
    icon(t, const Key('profile-ship-data-close'), source, settle: settle);
StarBridgeDialogRoute<void> route(WidgetTester t) =>
    ModalRoute.of(t.element(find.byKey(const Key('profile-ship-data-name'))))!
        as StarBridgeDialogRoute<void>;

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async =>
    t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      final dir = Directory('build/reviews/interaction-batch3au');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'grid-owned detail preserves actual activation source $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final key = GlobalKey<module_grid.GridState>();
          await mount(t, module_grid.Grid(key: key), suite, width: 1100);
          final state = key.currentState!;
          state.change(
            () => state.layout = [
              for (final item in state.layout)
                item.moduleId == 'favorite-ships'
                    ? item.copyWith(favoriteShipIds: [module_grid.a])
                    : item,
            ],
          );
          await settleCommunityImages(t);
          await action(
            t,
            Key('profile-favorite-ship-${module_grid.a}'),
            source,
            settle: false,
          );
          final current = route(t);
          expect(current.instant, source != 'pointer');
          expect(
            current.animation!.value,
            source == 'pointer' ? lessThan(1) : 1,
          );
          await settleCommunityImages(t);
          await close(t, source);
          expect(state.calls, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );
    }
    for (final reason in [
      'hide',
      'selection',
      'projection',
      'leave',
      'inactive',
      'unrelated',
    ]) {
      testWidgets(
        'grid-owned detail retires source without popping a different route $suite $reason',
        (t) async {
          final key = GlobalKey<module_grid.GridState>();
          bool active = true;
          late StateSetter update;
          await mount(
            t,
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return NativeViewportScope(
                  active: active,
                  child: module_grid.Grid(key: key),
                );
              },
            ),
            suite,
            width: 1100,
          );
          final state = key.currentState!;
          state.change(
            () => state.layout = [
              for (final item in state.layout)
                item.moduleId == 'favorite-ships'
                    ? item.copyWith(favoriteShipIds: [module_grid.a])
                    : item,
            ],
          );
          await settleCommunityImages(t);
          await action(
            t,
            Key('profile-favorite-ship-${module_grid.a}'),
            'pointer',
          );
          if (reason == 'unrelated') {
            unawaited(
              showStarBridgeDialog<void>(
                t.element(find.byKey(const Key('profile-ship-data-name'))),
                builder: (_) =>
                    const AlertDialog(title: Text('Unrelated top dialog')),
              ),
            );
            await t.pumpAndSettle();
          }
          if (reason == 'inactive') {
            update(() => active = false);
          } else {
            state.change(() {
              if (reason == 'projection') {
                state.data = state.data.copyWith(callSign: 'New source');
              } else if (reason == 'leave') {
                state.visible = false;
              } else {
                state.layout = [
                  for (final item in state.layout)
                    item.moduleId == 'favorite-ships'
                        ? item.copyWith(
                            isVisible: reason == 'selection',
                            position: reason == 'selection' ? 0 : -1,
                            favoriteShipIds: reason == 'selection'
                                ? []
                                : item.favoriteShipIds,
                          )
                        : item,
                ];
              }
            });
          }
          await t.pump();
          await t.pump();
          await settleCommunityImages(t);
          expect(find.byKey(const Key('profile-ship-data-name')), findsNothing);
          expect(state.calls, isEmpty);
          if (reason == 'unrelated') {
            expect(find.text('Unrelated top dialog'), findsOneWidget);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull);
        },
      );
    }
    for (final visitor in [false, true]) {
      testWidgets(
        'real page avatar fallback theme and DPI reflow do not revoke source $suite visitor=$visitor',
        (t) async {
          final port = PagePort();
          final module = createPersonalProfileModule(port);
          addTearDown(module.dispose);
          await module.initialize();
          final live = await mount(
            t,
            AccountAvatarScope(
              port: null,
              imageData: logo,
              editable: false,
              child: PersonalProfilePage(
                module: module,
                isVisitor: visitor,
                visitorAvatarImageData: logo,
              ),
            ),
            suite,
            width: 1100,
          );
          final source = module.projection.value;
          await action(
            t,
            const Key('profile-favorite-ship-ANVL_Carrack'),
            'pointer',
          );
          final current = route(t);
          live.change(() {
            live.light = true;
            live.reduce = true;
            live.suite = InteractionSuite.glow;
          });
          await t.pump();
          await t.pump();
          expect(identical(route(t), current), true);
          t.view.physicalSize = const Size(650, 700);
          await settleCommunityImages(t);
          expect(identical(module.projection.value, source), true);
          expect(identical(route(t), current), true);
          t.view.physicalSize = const Size(1280, 1000);
          await settleCommunityImages(t);
          expect(identical(route(t), current), true);
          expect(port.reads, 1);
          expect(port.writes, 0);
          await close(t, 'keyboard');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
    for (final reason in ['module', 'refresh']) {
      testWidgets(
        'real page new module or actual raw read retires prior details $suite $reason',
        (t) async {
          final a = PagePort(), b = PagePort();
          final first = createPersonalProfileModule(a),
              second = createPersonalProfileModule(b);
          addTearDown(first.dispose);
          addTearDown(second.dispose);
          await first.initialize();
          await second.initialize();
          var selected = first;
          late StateSetter update;
          await mount(
            t,
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return AccountAvatarScope(
                  port: null,
                  imageData: logo,
                  editable: false,
                  child: PersonalProfilePage(
                    key: const Key('real-page'),
                    module: selected,
                  ),
                );
              },
            ),
            suite,
            width: 1100,
          );
          await action(
            t,
            const Key('profile-favorite-ship-ANVL_Carrack'),
            'pointer',
          );
          if (reason == 'module') {
            update(() => selected = second);
          } else {
            await first.refresh();
          }
          await t.pump();
          await t.pump();
          await settleCommunityImages(t);
          expect(find.byKey(const Key('profile-ship-data-name')), findsNothing);
          expect(
            first.projection.value.availability,
            PersonalProfileAvailability.available,
          );
          expect(
            second.projection.value.availability,
            PersonalProfileAvailability.available,
          );
          expect(a.reads, reason == 'refresh' ? 2 : 1);
          expect(b.reads, 1);
          expect(a.writes, 0);
          expect(b.writes, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
    testWidgets(
      'real module grid detail survives wide narrow wide reflow $suite',
      (t) async {
        final key = GlobalKey<module_grid.GridState>();
        await mount(t, module_grid.Grid(key: key), suite, width: 1100);
        final state = key.currentState!;
        state.change(
          () => state.layout = [
            for (final item in state.layout)
              item.moduleId == 'favorite-ships'
                  ? item.copyWith(
                      size: PersonalProfileModuleSize.three,
                      favoriteShipIds: [module_grid.a],
                    )
                  : item,
          ],
        );
        await settleCommunityImages(t);
        final originalProjection = state.data;
        await action(
          t,
          Key('profile-favorite-ship-${module_grid.a}'),
          'pointer',
        );
        final current = route(t);
        t.view.physicalSize = const Size(600, 700);
        await settleCommunityImages(t);
        expect(identical(state.data, originalProjection), true);
        expect(find.byKey(const Key('profile-ship-data-name')), findsOneWidget);
        expect(identical(route(t), current), true);
        final hero = t.getRect(find.byKey(const Key('profile-ship-data-hero')));
        expect(hero.width / hero.height, closeTo(1200 / 420, .01));
        t.view.physicalSize = const Size(1280, 1000);
        await settleCommunityImages(t);
        expect(identical(route(t), current), true);
        expect(state.calls, isEmpty);
        await close(t, 'keyboard');
        expect(t.takeException(), isNull);
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'favorite card source and exact authorized facts without reads or writes $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final (_, _, port) = await shelf(
            t,
            suite,
            initial: ship('a', former: true),
          );
          final before = t.getRect(
            find.byKey(const Key('profile-favorite-ship-a')),
          );
          await open(t, source, settle: false);
          final current = route(t);
          expect(current.instant, source != 'pointer');
          expect(
            current.animation!.value,
            source == 'pointer' ? lessThan(1) : 1,
          );
          await settleCommunityImages(t);
          expect(fact('克拉克 a'), findsOneWidget);
          expect(fact('Carrack a'), findsOneWidget);
          expect(fact('Anvil'), findsOneWidget);
          expect(fact('\$600'), findsOneWidget);
          expect(fact('曾拥有'), findsOneWidget);
          expect(fact('Never invent a crew fact'), findsNothing);
          final hero = t.getRect(
            find.byKey(const Key('profile-ship-data-hero')),
          );
          expect(hero.width / hero.height, closeTo(1200 / 420, .01));
          expect(hero.center.dx, closeTo(t.getRect(detail).center.dx, 1));
          expect(
            t.getRect(find.byKey(const Key('profile-ship-data-facts'))).top,
            greaterThan(hero.bottom),
          );
          expect(port.targets, isEmpty);
          expect(port.commands, 0);
          await close(t, source, settle: false);
          if (source == 'pointer') {
            expect(current.animation!.status, AnimationStatus.reverse);
            expect(detail, findsOneWidget);
          } else {
            expect(detail, findsNothing);
          }
          await settleCommunityImages(t);
          expect(
            t.getRect(find.byKey(const Key('profile-favorite-ship-a'))),
            before,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );
    }

    for (final reason in [
      'replace',
      'remove',
      'leave',
      'inactive',
      'unrelated',
    ]) {
      testWidgets(
        'favorite details retire only their exact source $suite $reason',
        (t) async {
          final (state, _, port) = await shelf(t, suite);
          final semantics = t.ensureSemantics();
          await open(t, 'pointer');
          if (reason == 'unrelated') {
            final caller = t.element(
              find.byKey(const Key('profile-ship-data-name')),
            );
            unawaited(
              showStarBridgeDialog<void>(
                caller,
                builder: (_) =>
                    const AlertDialog(title: Text('Unrelated top dialog')),
              ),
            );
            await t.pumpAndSettle();
          }
          state.change(() {
            if (reason == 'replace') {
              state.values = [
                ship('a', name: 'New metadata'),
                state.values.last,
              ];
            } else if (reason == 'remove' || reason == 'unrelated') {
              state.values = [state.values.last];
            } else if (reason == 'leave') {
              state.visible = false;
            } else {
              state.active = false;
            }
          });
          await t.pump();
          await t.pump();
          await settleCommunityImages(t);
          expect(find.byKey(const Key('profile-ship-data-name')), findsNothing);
          if (reason == 'unrelated') {
            expect(find.text('Unrelated top dialog'), findsOneWidget);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pumpAndSettle();
          }
          if (reason == 'inactive') {
            final node = t.getSemantics(
              find.byKey(const Key('profile-favorite-ship-a')),
            );
            expect(
              node.getSemanticsData().hasAction(SemanticsAction.tap),
              false,
            );
          }
          expect(port.targets, isEmpty);
          expect(port.commands, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );
    }

    testWidgets(
      'reordering same instances retains the owned detail and card state $suite',
      (t) async {
        final (state, _, _) = await shelf(t, suite);
        await open(t, 'pointer');
        final original = route(t);
        state.change(() => state.values = state.values.reversed.toList());
        await settleCommunityImages(t);
        expect(identical(route(t), original), true);
        expect(fact('克拉克 a'), findsOneWidget);
        await close(t, 'keyboard');
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'favorite detail stays open through live style palette reduce and preserves original media $suite',
      (t) async {
        final (state, live, _) = await shelf(t, suite);
        await open(t, 'pointer');
        final current = route(t);
        final hero = find.descendant(
          of: find.byKey(const Key('profile-ship-data-hero')),
          matching: find.byType(Image),
        );
        final mediaState = t.element(hero);
        final geometry = t.getRect(
          find.byKey(const Key('profile-ship-data-hero')),
        );
        live.change(() {
          live.suite = InteractionSuite.scan;
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(identical(route(t), current), true);
        expect(identical(t.element(hero), mediaState), true);
        expect(
          (t.widget<Image>(hero).image as AssetImage).assetName,
          'assets/ships/catalog-carrack.png',
        );
        expect(t.widget<Image>(hero).fit, BoxFit.contain);
        expect(
          t.getRect(find.byKey(const Key('profile-ship-data-hero'))),
          geometry,
        );
        expect(
          InteractionScope.of(
            t.element(find.byKey(const Key('profile-ship-data-name'))),
          ).reduceMotion,
          true,
        );
        expect(state.values.first.identity.runtimeId, 'a');
        await close(t, 'keyboard');
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'favorite reduce during entrance and exit settles in two frames $suite',
      (t) async {
        final (_, live, _) = await shelf(t, suite);
        await open(t, 'pointer', settle: false);
        final current = route(t);
        expect(current.animation!.value, lessThan(1));
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        expect(current.animation!.value, 1);
        expect(current.animation!.isAnimating, false);
        live.change(() => live.reduce = false);
        await t.pump();
        await t.pump();
        await close(t, 'pointer', settle: false);
        expect(current.animation!.status, AnimationStatus.reverse);
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        expect(detail, findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    for (final dismiss in ['escape', 'barrier']) {
      testWidgets(
        'favorite $dismiss closes and retains the original source $suite',
        (t) async {
          final (state, _, _) = await shelf(t, suite);
          final objects = state.values;
          await open(t, 'pointer');
          if (dismiss == 'escape') {
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            await t.pump();
            expect(detail, findsNothing);
          } else {
            await t.tapAt(const Offset(12, 12));
            await t.pumpAndSettle();
          }
          expect(detail, findsNothing);
          expect(identical(state.values, objects), true);
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets('actual media failure keeps facts and can be closed $suite', (
      t,
    ) async {
      await shelf(
        t,
        suite,
        initial: ship(
          'a',
          image: 'missing-wide.jpg',
          thumbnail: 'missing-square.png',
        ),
      );
      await open(t, 'pointer');
      expect(fact('克拉克 a'), findsOneWidget);
      expect(fact('Anvil'), findsOneWidget);
      expect(fact('\$600'), findsOneWidget);
      await close(t, 'keyboard');
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'overview catalog-price hint follows suite and bounded window $suite',
      (t) async {
        final live = await mount(
          t,
          const Center(
            child: SizedBox(
              height: 140,
              child: PersonalProfileHangarOverview(summary: summary, span: 3),
            ),
          ),
          suite,
          width: 1100,
        );
        final panel = find.byKey(const Key('profile-hangar-value-panel'));
        final hint = t.widget<StarBridgeTooltip>(
          find.descendant(of: panel, matching: find.byType(StarBridgeTooltip)),
        );
        expect(
          hint.message,
          AppStrings.of(t.element(panel)).text('profile.local.catalogPrice'),
        );
        final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
        await pointer.addPointer(location: Offset.zero);
        await pointer.moveTo(t.getCenter(panel));
        await t.pump(const Duration(milliseconds: 450));
        await t.pump(const Duration(milliseconds: 500));
        final message = find.text(hint.message);
        expect(message, findsOneWidget);
        final bounds = t.getRect(message);
        expect(bounds.left, greaterThanOrEqualTo(8));
        expect(bounds.right, lessThanOrEqualTo(1272));
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(find.text('\$1,200 USD'), findsOneWidget);
        await pointer.removePointer();
        await settleCommunityImages(t);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'all favorite pointer activations are retained without replaying hidden commands $suite',
      (t) async {
        final (_, _, port) = await shelf(t, suite);
        for (var i = 0; i < 4; i++) {
          await open(t, 'pointer', settle: false);
          final current = route(t);
          expect(current.animation!.value, lessThan(1));
          await close(t, 'keyboard', settle: false);
          expect(detail, findsNothing);
        }
        expect(port.targets, isEmpty);
        expect(port.commands, 0);
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('favorite detail and exit review $suite', (t) async {
      final boundary = GlobalKey();
      await shelf(
        t,
        suite,
        capture: boundary,
        initial: ship('a', former: true),
      );
      await open(t, 'pointer');
      await capture(t, boundary, '${suite.name}-detail');
      final hero = find.descendant(
        of: find.byKey(const Key('profile-ship-data-hero')),
        matching: find.byType(RawImage),
      );
      if (File('assets/ships/catalog-carrack.png').existsSync()) {
        expect(t.widget<RawImage>(hero).image, isNotNull);
        expect(t.widget<RawImage>(hero).image!.width, greaterThan(300));
        expect(t.widget<RawImage>(hero).image!.height, greaterThan(100));
      } else {
        // Optional licensed artwork is absent; detail and exit still run.
        expect(hero, findsNothing);
        expect(find.byKey(const Key('profile-ship-data-hero')), findsOneWidget);
        expect(t.takeException(), isNull);
      }
      await close(t, 'pointer', settle: false);
      await t.pump(const Duration(milliseconds: 40));
      await capture(t, boundary, '${suite.name}-exit');
      await settleCommunityImages(t);
      expect(detail, findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
