import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

import 'interaction_batch3at_test.dart' as profile;
import 'interaction_batch3aw_test.dart' show frame, animation;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;

/// Snapshot every module, including normalize's non-visible defaults. The full
/// result is not a single favorite module and may never be narrowed to one.
List<Map<String, Object?>> _layoutValues(
  Iterable<PersonalProfileModuleLayoutItem> layout,
) => [
  for (final item in layout)
    {
      'moduleId': item.moduleId,
      'size': item.size,
      'isVisible': item.isVisible,
      'position': item.position,
      'favoriteShipIds': item.favoriteShipIds?.toList(),
    },
];

FocusNode _entryOwner(WidgetTester t, Finder target) {
  expect(target, findsOneWidget);
  final widget = t.widget(target);
  if (widget is SuitePressable) {
    expect(widget.onActivate, isNotNull);
    return widget.focusNode!;
  }
  expect(widget, isA<MenuItemButton>());
  final native = widget as MenuItemButton;
  expect(native.onPressed, isNotNull);
  return native.focusNode!;
}

/// Public focus nodes are observed, never requested. Both the anchor and entry
/// are reached through actual keyboard traversal of the real product menu.
Future<void> _tabEnter(WidgetTester t, FocusNode owner) async {
  expect(owner.canRequestFocus, isTrue);
  var tabs = 0;
  do {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await frame(t);
    tabs++;
  } while (!owner.hasPrimaryFocus && tabs < 48);
  expect(tabs, inInclusiveRange(1, 48));
  expect(FocusManager.instance.primaryFocus, same(owner));
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await frame(t);
}

Future<void> _arrowEnter(WidgetTester t, FocusNode owner) async {
  expect(owner.canRequestFocus, isTrue);
  var arrows = 0;
  do {
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await frame(t);
    arrows++;
  } while (!owner.hasPrimaryFocus && arrows < 16);
  expect(arrows, inInclusiveRange(1, 16));
  expect(FocusManager.instance.primaryFocus, same(owner));
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await frame(t);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final failure in ['capacity', 'space']) {
      testWidgets(
        '$suite real Tab Arrow Enter grid $failure preserves the complete original layout and static error toast',
        (t) async {
          final semantics = t.ensureSemantics();
          // The original fixture sets width 1100 and mounts the actual grid,
          // projection, menu callbacks and onLayoutChanged recorder.
          final (state, _) = await profile.grid(t, suite);
          try {
            state.change(
              () => state.layout = PersonalProfileLayout.normalize(
                failure == 'capacity'
                    ? [
                        profile.item.copyWith(
                          size: PersonalProfileModuleSize.two,
                          favoriteShipIds: [profile.a, profile.b],
                        ),
                      ]
                    : [
                        for (var i = 0; i < 64; i++)
                          PersonalProfileModuleLayoutItem(
                            moduleId: i == 0
                                ? 'favorite-ships'
                                : 'favorite-ships-$i',
                            size: PersonalProfileModuleSize.three,
                            isVisible: true,
                            position: i * 3,
                            favoriteShipIds: const [],
                          ),
                      ],
              ),
            );
            await settleCommunityImages(t);
            final before = state.layout;
            final data = state.data;
            final completeValues = _layoutValues(before);
            expect(state.calls, isEmpty);
            if (failure == 'capacity') {
              final favorites = before.singleWhere(
                (item) => item.moduleId == 'favorite-ships',
              );
              expect(favorites.size, PersonalProfileModuleSize.two);
              expect(favorites.favoriteShipIds, [profile.a, profile.b]);
              expect(favorites.isVisible, isTrue);
            } else {
              final visible = before.where((item) => item.isVisible).toList();
              expect(visible, hasLength(64));
              for (var i = 0; i < 64; i++) {
                final module = before.singleWhere(
                  (item) =>
                      item.moduleId ==
                      (i == 0 ? 'favorite-ships' : 'favorite-ships-$i'),
                );
                expect(module.size, PersonalProfileModuleSize.three);
                expect(module.isVisible, isTrue);
                expect(module.position, i * 3);
                expect(module.favoriteShipIds, isEmpty);
              }
              expect(
                before
                    .singleWhere((item) => item.moduleId == 'hangar-summary')
                    .isVisible,
                isFalse,
              );
            }

            final anchorKey = failure == 'capacity'
                ? const Key('profile-module-size-favorite-ships')
                : const Key('profile-add-module-anchor');
            final Object identity = failure == 'capacity'
                ? (
                    'profile-module-size-favorite-ships',
                    PersonalProfileModuleSize.one,
                  )
                : ('profile-add-module', 'hangar-summary');
            final target = find.byKey(anchorKey).first;
            expect(target, findsOneWidget);
            await t.ensureVisible(target);
            await frame(t);
            final anchor = t.widget<SuitePressable>(target);
            expect(anchor.onActivate, isNotNull);
            final owner = anchor.focusNode!;
            final menuFinder = find
                .ancestor(
                  of: target,
                  matching: find.byType(StarBridgeMenuAnchor),
                )
                .first;
            final config = t.widget<StarBridgeMenuAnchor>(menuFinder);
            expect(config.enabled, isTrue);
            expect(
              config.entries
                  .singleWhere((entry) => entry.id == identity)
                  .onActivate,
              isNotNull,
            );
            final option = find.byKey(ValueKey<Object>(identity));
            expect(option, findsNothing);

            await _tabEnter(t, owner);
            await settleCommunityImages(t);
            expect(option, findsOneWidget);
            expect(state.layout, same(before));
            expect(state.data, same(data));
            expect(_layoutValues(state.layout), completeValues);
            expect(state.calls, isEmpty);
            await _arrowEnter(t, _entryOwner(t, option));

            // This is the original grid's business failure and localization,
            // reached through its menu's real activation/source propagation.
            // No replacement onActivate or synthetic error toast is supplied.
            final label = AppStrings.of(state.context).text(
              failure == 'capacity'
                  ? 'profile.favorites.resize'
                  : 'profile.layout.noSpace',
            );
            expect(find.text(label), findsOneWidget);
            expect(state.layout, same(before));
            expect(state.data, same(data));
            expect(_layoutValues(state.layout), completeValues);
            expect(
              PersonalProfileLayout.hasSameLayout(state.layout, before),
              isTrue,
            );
            expect(state.calls, isEmpty);
            final toast = animation(t);
            expect(toast.isAnimating, isFalse);
            expect(toast.value, 1);
            await t.pump(const Duration(milliseconds: 200));
            await frame(t);
            expect(animation(t), same(toast));
            expect(toast.isAnimating, isFalse);
            expect(toast.value, 1);
            expect(find.text(label), findsOneWidget);
            expect(state.layout, same(before));
            expect(state.data, same(data));
            expect(_layoutValues(state.layout), completeValues);
            expect(state.calls, isEmpty);
            // The exact controller endpoint is a motion-policy assertion, not
            // a claim of device rendering or pixel-level visual acceptance.
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await frame(t);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}
