import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_expansion_tile.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_filter_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_catalog.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_colors.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3et_test.dart' show activate;
import 'interaction_batch3i_test.dart' show scopedApp, mount;

class FilterProbe {
  Set<String> selected = const {'combat'};
  final requests = <Set<String>>[];
  final sources = <InteractionSource>[];
  final bucket = PageStorageBucket();
  bool accept = true, visible = true, reduce = false, light = false;
  bool nativeSeed = false;
  late InteractionSuite suite;
  late StateSetter update;

  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        PageStorage(
          bucket: bucket,
          child: SizedBox(
            width: 290,
            child: !visible
                ? const SizedBox()
                : nativeSeed
                ? ListView(
                    key: const PageStorageKey('room-filter-scroll'),
                    children: const [
                      ExpansionTile(
                        key: PageStorageKey('room-filter-branch-combat'),
                        title: Text('战斗'),
                        children: [
                          ExpansionTile(
                            key: PageStorageKey('room-filter-branch-pve'),
                            title: Text('PVE'),
                            children: [Text('native seed')],
                          ),
                        ],
                      ),
                    ],
                  )
                : RoomFilterPanel(
                    options: RoomTagCatalog.exampleOptions,
                    selected: selected,
                    onChanged: (value) {
                      requests.add(value);
                      sources.add(currentStarBridgeActivationSource);
                      if (accept) update(() => selected = value);
                    },
                  ),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Finder disclosure(String id) => find.byKey(
  PageStorageKey(
    'room-filter-${id.startsWith('context-') ? id : 'branch-$id'}',
  ),
);
Finder header(String id) => find
    .descendant(of: disclosure(id), matching: find.byType(SuitePressable))
    .first;
Finder choice(String id) => find.ancestor(
  of: find.byKey(ValueKey('room-filter-$id')),
  matching: find.byType(StarBridgeCheckboxTile),
);
Finder clearFilter() => find.byKey(const Key('room-filter-clear'));
Future<void> activateChoice(WidgetTester t, String id, String source) async {
  final target = choice(id);
  if (source == 'pointer') {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }
  await activate(t, target, source);
}

Future<void> activateHeader(WidgetTester t, String id, String source) async {
  final target = header(id);
  if (source == 'pointer') {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }
  await activate(t, target, source);
}

bool expanded(WidgetTester t, String id) => t
    .widget<SuiteExpander>(
      find
          .descendant(of: disclosure(id), matching: find.byType(SuiteExpander))
          .first,
    )
    .expanded;
Future<FilterProbe> panel(WidgetTester t, InteractionSuite suite) async {
  size(t, const Size(500, 1400));
  final p = FilterProbe()..suite = suite;
  await t.pumpWidget(p.app());
  await t.pumpAndSettle();
  return p;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite persistent filters $source keep catalog and callbacks',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await panel(t, suite);
            expect(find.byType(StarBridgeExpansionTile), findsWidgets);
            await activateHeader(t, 'combat', source);
            await t.pumpAndSettle();
            await activateHeader(t, 'pve', source);
            await t.pumpAndSettle();
            await activateChoice(t, 'pve_bounty', source);
            await t.pumpAndSettle();
            expect(p.selected, {'pve_bounty'});
            expect(
              p.sources.single,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            await activateHeader(t, 'pvp', source);
            await t.pumpAndSettle();
            await activateChoice(t, 'pvp_fps', source);
            await t.pumpAndSettle();
            expect(p.selected, {'pve_bounty', 'pvp_fps'});
            await activateChoice(t, 'combat', source);
            await t.pumpAndSettle();
            expect(p.selected, {'combat'});
            await activateChoice(t, 'combat', source);
            await t.pumpAndSettle();
            expect(p.selected, isEmpty);
            expect(p.requests, hasLength(4));
            final button = t.widget<StarBridgeActionButton>(
              find.byType(StarBridgeActionButton),
            );
            expect(button.onActivate, isNull);
            await activateHeader(t, 'combat', source);
            await t.pumpAndSettle();
            await activateHeader(t, 'context-need', source);
            await t.pumpAndSettle();
            await activateChoice(t, 'need_pilot', source);
            await t.pumpAndSettle();
            expect(p.selected, {'need_pilot'});
            expect(p.requests, hasLength(5));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
    for (final source in ['keyboard', 'reader']) {
      testWidgets(
        '$suite filter disclosure $source lands without running motion',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            await panel(t, suite);
            await activate(t, header('combat'), source);
            expect(expanded(t, 'combat'), isTrue);
            expect(t.hasRunningAnimations, isFalse);
            await activate(t, header('combat'), source);
            expect(expanded(t, 'combat'), isFalse);
            expect(t.hasRunningAnimations, isFalse);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite controlled filter rejects update without optimistic selection',
      (t) async {
        final p = await panel(t, suite);
        expect(find.byType(StarBridgeExpansionTile), findsWidgets);
        await activate(t, header('combat'), 'keyboard');
        await t.pumpAndSettle();
        p.accept = false;
        for (var i = 0; i < 3; i++) {
          await activate(t, choice('combat'), 'pointer');
          await t.pump(const Duration(milliseconds: 25));
          expect(p.selected, {'combat'});
          expect(
            t.widget<StarBridgeCheckboxTile>(choice('combat')).value,
            isTrue,
          );
        }
        expect(p.requests, [<String>{}, <String>{}, <String>{}]);
        p.accept = true;
        await activate(t, clearFilter(), 'keyboard');
        await t.pumpAndSettle();
        expect(p.selected, isEmpty);
        expect(p.sources.last, InteractionSource.keyboard);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite native expansion storage and live settings retain filter owner',
      (t) async {
        size(t, const Size(500, 1400));
        final p = FilterProbe()
          ..suite = suite
          ..nativeSeed = true;
        await t.pumpWidget(p.app());
        await t.pumpAndSettle();
        await t.tap(find.byType(ExpansionTile));
        await t.pumpAndSettle();
        await t.tap(disclosure('pve'));
        await t.pumpAndSettle();
        p.update(() => p.nativeSeed = false);
        await t.pumpAndSettle();
        expect(expanded(t, 'combat'), isTrue);
        expect(expanded(t, 'pve'), isTrue);
        final owner = p.selected;
        p.update(() {
          p.light = true;
          p.reduce = true;
          p.suite = InteractionSuite.glow;
        });
        await t.pumpAndSettle();
        expect(expanded(t, 'combat'), isTrue);
        expect(expanded(t, 'pve'), isTrue);
        expect(p.selected, same(owner));
        expect(p.requests, isEmpty);
        p.update(() => p.visible = false);
        await t.pumpAndSettle();
        p.update(() => p.visible = true);
        await t.pumpAndSettle();
        expect(expanded(t, 'combat'), isTrue);
        expect(expanded(t, 'pve'), isTrue);
        await activate(t, header('combat'), 'keyboard');
        await t.pumpAndSettle();
        expect(disclosure('pve'), findsNothing);
        await activate(t, header('combat'), 'keyboard');
        await t.pumpAndSettle();
        expect(expanded(t, 'pve'), isTrue);
        expect(p.selected, same(owner));
        final tile = t.widget<StarBridgeCheckboxTile>(choice('combat'));
        expect(
          tile.activeColor,
          roomTagColors(t.element(choice('combat')), 'combat').foreground,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite repeated active disclosure feedback and reduce interruption',
      (t) async {
        final p = await panel(t, suite);
        expect(find.byType(StarBridgeExpansionTile), findsWidgets);
        await activate(t, header('combat'), 'pointer');
        await t.pump(const Duration(milliseconds: 35));
        expect(expanded(t, 'combat'), isTrue);
        if (suite != InteractionSuite.standard) {
          expect(t.hasRunningAnimations, isTrue);
        }
        await activate(t, header('combat'), 'pointer');
        await t.pump(const Duration(milliseconds: 20));
        expect(expanded(t, 'combat'), isFalse);
        await activate(t, header('combat'), 'pointer');
        await t.pump(const Duration(milliseconds: 20));
        expect(expanded(t, 'combat'), isTrue);
        p.update(() => p.reduce = true);
        await t.pump();
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        expect(p.requests, isEmpty);
        await activate(t, header('combat'), 'keyboard');
        await t.pump();
        expect(expanded(t, 'combat'), isFalse);
        expect(choice('combat'), findsNothing);
        expect(t.hasRunningAnimations, isFalse);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite actual directory retains selected filters across width and cancel',
      (t) async {
        final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
        await mount(t, module, suite);
        expect(find.byType(StarBridgeExpansionTile), findsWidgets);
        await activate(t, header('combat'), 'keyboard');
        await t.pumpAndSettle();
        await activate(t, choice('combat'), 'keyboard');
        await t.pumpAndSettle();
        expect(
          t.widget<StarBridgeCheckboxTile>(choice('combat')).value,
          isTrue,
        );
        final directory = module.directory;
        t.view.physicalSize = const Size(1000, 1000);
        await t.pumpAndSettle();
        expect(find.text('筛选标签 · 1'), findsOneWidget);
        await activate(
          t,
          find.byKey(const Key('rooms-tag-filter')),
          'keyboard',
        );
        await t.pumpAndSettle();
        await activate(
          t,
          find.widgetWithText(StarBridgeActionButton, '取消'),
          'keyboard',
        );
        await t.pumpAndSettle();
        expect(find.text('筛选标签 · 1'), findsOneWidget);
        t.view.physicalSize = const Size(1280, 1000);
        await t.pumpAndSettle();
        if (!expanded(t, 'combat')) {
          await activate(t, header('combat'), 'keyboard');
          await t.pumpAndSettle();
        }
        expect(
          t.widget<StarBridgeCheckboxTile>(choice('combat')).value,
          isTrue,
        );
        expect(module.directory, same(directory));
        expect(module.directory!.currentRoomId, isNull);
        module.stopSession();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
}
