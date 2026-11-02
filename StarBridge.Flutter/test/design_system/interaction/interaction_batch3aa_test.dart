import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_compact_select.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_controls.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_toolbar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_row.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_card.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3z_test.dart' show Inbox;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

const controlKey = Key('compact');
const options = [
  StarBridgeSelectOption(value: 'a', label: 'Alpha'),
  StarBridgeSelectOption(value: 'blocked', label: 'Disabled', enabled: false),
  StarBridgeSelectOption(value: 'b', label: 'Bravo'),
];

class Harness extends StatefulWidget {
  const Harness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  var choices = options;
  String? value = 'a';
  bool enabled = true, visible = true, reduce = false, apply = false;
  final calls = <(String, InteractionSource)>[];
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    Center(
      child: visible
          ? StarBridgeCompactSelect<String>(
              controlKey: controlKey,
              identity: 'compact',
              semanticLabel: '字段',
              options: choices,
              value: value,
              onSelected: enabled
                  ? (next, source) {
                      calls.add((next, source));
                      if (apply) setState(() => value = next);
                    }
                  : null,
            )
          : const Text('离开页面'),
    ),
    suite,
    reduce: reduce,
  );
}

Future<HarnessState> harness(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

void reader(WidgetTester t, String label) {
  final nodes = exposedNodes(t)
      .where(
        (n) =>
            n.getSemanticsData().label == label &&
            n.getSemanticsData().hasAction(SemanticsAction.tap),
      )
      .toList();
  expect(nodes, hasLength(1));
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    nodes.single.id,
    SemanticsAction.tap,
  );
}

Future<void> open(WidgetTester t, Key key, String source) async {
  final target = find.byKey(key);
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    t.widget<SuitePressable>(target).focusNode!.requestFocus();
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final anchor = find
        .ancestor(of: target, matching: find.byType(StarBridgeMenuAnchor))
        .first;
    reader(t, t.widget<StarBridgeMenuAnchor>(anchor).semanticLabel);
  }
  await t.pump();
  await t.pump();
}

Future<void> select(
  WidgetTester t,
  Object identity,
  Object value,
  String source,
) async {
  final row = find.byKey(ValueKey<Object>((identity, value)));
  if (source == 'pointer') {
    await t.tap(row);
  } else if (source == 'keyboard') {
    final widget = t.widget(row);
    final node = widget is SuitePressable
        ? widget.focusNode!
        : (widget as MenuItemButton).focusNode!;
    node.requestFocus();
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final label = t
        .widget<StarBridgeMenuAnchor>(find.byType(StarBridgeMenuAnchor).first)
        .entries
        .singleWhere((e) => e.id == (identity, value))
        .label;
    reader(t, label);
  }
  await t.pump();
  await t.pump();
}

class LocalPort implements LocalHangarPort {
  var reads = 0, saves = 0;
  final snapshot = LocalHangarSnapshot(
    revision: 4,
    savedAt: DateTime(2026),
    ships: [
      LocalHangarShip(
        id: 'z',
        title: 'Zulu',
        addedAt: DateTime(2026, 1, 1),
        priceUsd: 100,
      ),
      LocalHangarShip(
        id: 'a',
        title: 'Alpha',
        addedAt: DateTime(2026, 2, 1),
        priceUsd: 200,
      ),
    ],
  );
  @override
  Future<LocalHangarSnapshot> read() async {
    reads++;
    return snapshot;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    saves++;
    throw StateError('Sorting must not save a scan.');
  }
}

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async {
  await t.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3aa');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $source compact menu controlled and one callback', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          final state = await harness(t, suite);
          await open(t, controlKey, source);
          final surface = t.widget<SuiteSurfaceTransition>(
            find.byType(SuiteSurfaceTransition),
          );
          if (source != 'pointer') expect(surface.animation.value, 1);
          await t.pumpAndSettle();
          await select(t, 'compact', 'b', source);
          expect(state.calls, [
            (
              'b',
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ),
          ]);
          // Only the owner may accept or reject this requested choice.
          expect(state.value, 'a');
          await t.pumpAndSettle();
          expect(find.byType(SuiteSurfaceTransition), findsNothing);
          state.change(() => state.value = 'b');
          await t.pumpAndSettle();
          final header = t.widget<DropdownButton<String>>(
            find.descendant(
              of: find.byKey(controlKey),
              matching: find.byType(DropdownButton<String>),
            ),
          );
          expect(header.value, 'b');
          expect(state.calls, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
      testWidgets('$suite $source menu disabled option remains inaccessible', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          final state = await harness(t, suite);
          await open(t, controlKey, source);
          await t.pumpAndSettle();
          final node = exposedNodes(t)
              .singleWhere((n) => n.getSemanticsData().label == 'Disabled');
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isFalse,
          );
          await t.tap(
            find.byKey(const ValueKey<Object>(('compact', 'blocked'))),
            warnIfMissed: false,
          );
          await t.pumpAndSettle();
          expect(state.calls, isEmpty);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.byType(SuiteSurfaceTransition), findsNothing);
          expect(
            t
                .widget<SuitePressable>(find.byKey(controlKey))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
    testWidgets(
      '$suite live reduce lands open menu and keyboard Esc is instant',
      (t) async {
        final state = await harness(t, suite);
        await open(t, controlKey, 'pointer');
        await t.pump(const Duration(milliseconds: 35));
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        expect(
          t
              .widget<SuiteSurfaceTransition>(
                find.byType(SuiteSurfaceTransition),
              )
              .animation
              .value,
          1,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(find.byType(SuiteSurfaceTransition), findsNothing);
        expect(state.calls, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite dynamic removal and reordering do not use stale rows', (
      t,
    ) async {
      final state = await harness(t, suite);
      await open(t, controlKey, 'keyboard');
      state.change(
        () => state.choices = [
          options.last,
          const StarBridgeSelectOption(value: 'c', label: 'Charlie'),
        ],
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<Object>(('compact', 'a'))),
        findsNothing,
      );
      await select(t, 'compact', 'c', 'keyboard');
      await t.pumpAndSettle();
      expect(state.calls, [('c', InteractionSource.keyboard)]);
      expect(state.value, 'a');
      expect(t.takeException(), isNull);
    });
    testWidgets('$suite disabled and empty options close without selecting', (
      t,
    ) async {
      final state = await harness(t, suite);
      await open(t, controlKey, 'pointer');
      state.change(() => state.enabled = false);
      await t.pump();
      await t.pump();
      await t.pumpAndSettle();
      expect(find.byType(SuiteSurfaceTransition), findsNothing);
      await t.tap(find.byKey(controlKey), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(state.calls, isEmpty);
      state.change(() {
        state.enabled = true;
        state.choices = [
          for (final option in options)
            StarBridgeSelectOption(
              value: option.value,
              label: option.label,
              enabled: false,
            ),
        ];
      });
      await t.pumpAndSettle();
      await t.tap(find.byKey(controlKey), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byType(SuiteSurfaceTransition), findsNothing);
      state.change(() {
        state.choices = [];
      });
      await t.pumpAndSettle();
      await t.tap(find.byKey(controlKey), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byType(SuiteSurfaceTransition), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('$suite compact header has one keyboard focus target', (
      t,
    ) async {
      final before = FocusNode(), after = FocusNode();
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await t.pumpWidget(
        scopedApp(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                focusNode: before,
                onPressed: () {},
                child: const Text('之前'),
              ),
              StarBridgeCompactSelect<String>(
                controlKey: controlKey,
                identity: 'compact',
                semanticLabel: '字段',
                options: options,
                value: 'a',
                onSelected: (_, _) {},
              ),
              TextButton(
                focusNode: after,
                onPressed: () {},
                child: const Text('之后'),
              ),
            ],
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      before.requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(
        t.widget<SuitePressable>(find.byKey(controlKey)).focusNode!.hasFocus,
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(after.hasFocus, isTrue);
      expect(find.byType(SuiteSurfaceTransition), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    testWidgets('$suite rapid reopen reverses one menu not a queue', (t) async {
      final state = await harness(t, suite);
      await open(t, controlKey, 'pointer');
      await t.pump(const Duration(milliseconds: 40));
      final oldSurface = t.state(find.byType(SuiteSurfaceTransition));
      await t.tap(find.byKey(controlKey));
      await t.pump(const Duration(milliseconds: 20));
      await t.tap(find.byKey(controlKey));
      await t.pump();
      expect(find.byType(SuiteSurfaceTransition), findsOneWidget);
      expect(t.state(find.byType(SuiteSurfaceTransition)), same(oldSurface));
      await t.pumpAndSettle();
      await select(t, 'compact', 'b', 'pointer');
      await t.pumpAndSettle();
      expect(state.calls, [('b', InteractionSource.pointer)]);
      expect(t.takeException(), isNull);
    });
    testWidgets(
      '$suite leaving with open menu disposes portal and does not select',
      (t) async {
        final state = await harness(t, suite);
        await open(t, controlKey, 'pointer');
        state.change(() => state.visible = false);
        await t.pumpAndSettle();
        expect(find.byType(SuiteSurfaceTransition), findsNothing);
        expect(state.calls, isEmpty);
        expect(find.text('离开页面'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
    for (final kind in ['members', 'ships']) {
      testWidgets('$suite actual fleet $kind page-size owner retained', (
        t,
      ) async {
        size(t, const Size(1200, 800));
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        if (kind == 'members') {
          final module = createOfficialFleetMembersModule(
            InMemoryOfficialFleetMembersAdapter.forReview(),
          );
          addTearDown(module.dispose);
          await module.open('officialFleet:7');
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder(
                valueListenable: module.projection,
                builder: (_, p, _) => OfficialFleetMembersPagination(
                  projection: p,
                  module: module,
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await open(
            t,
            const Key('official-fleet-members-page-size'),
            'keyboard',
          );
          await select(t, 'official-fleet-members-page-size', 25, 'keyboard');
          await t.pumpAndSettle();
          expect(module.projection.value.query!.pageSize, 25);
          expect(module.projection.value.query!.sourceRef, 'officialFleet:7');
        } else {
          final module = createOfficialFleetShipsModule(
            InMemoryOfficialFleetShipsAdapter.forReview(),
          );
          addTearDown(module.dispose);
          await module.open('officialFleet:7');
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder(
                valueListenable: module.projection,
                builder: (_, p, _) => OfficialFleetShipsToolbar(
                  projection: p,
                  module: module,
                  searchController: controller,
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await open(t, const Key('official-fleet-ships-page-size'), 'pointer');
          await t.pumpAndSettle();
          await select(t, 'official-fleet-ships-page-size', 100, 'pointer');
          await t.pumpAndSettle();
          expect(module.projection.value.query!.pageSize, 100);
          expect(module.projection.value.query!.sourceRef, 'officialFleet:7');
          expect(module.projection.value.ships, hasLength(6));
        }
        expect(t.takeException(), isNull);
      });
    }
    testWidgets('$suite notification category uses original local filter', (
      t,
    ) async {
      size(t, const Size(1200, 850));
      final inbox = Inbox();
      addTearDown(inbox.dispose);
      await t.pumpWidget(
        scopedApp(NotificationInboxPage(controller: inbox), suite),
      );
      await t.pumpAndSettle();
      await open(t, const Key('notification-category'), 'keyboard');
      await select(t, 'notification-category', 'system', 'keyboard');
      await t.pumpAndSettle();
      expect(find.text('普通通知'), findsOneWidget);
      expect(find.text('待处理通知'), findsNothing);
      expect(inbox.items, hasLength(2));
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    testWidgets('$suite hangar sort changes presentation not saved inventory', (
      t,
    ) async {
      size(t, const Size(1200, 1100));
      final port = LocalPort();
      await t.pumpWidget(
        scopedApp(LocalHangarPage(port: port, onRead: () {}), suite),
      );
      await t.pumpAndSettle();
      await open(t, const Key('hangar-sort'), 'keyboard');
      await select(t, 'hangar-sort', 'name', 'keyboard');
      await t.pumpAndSettle();
      expect(
        t
            .widget<StarBridgeCompactSelect<String>>(
              find.byType(StarBridgeCompactSelect<String>),
            )
            .value,
        'name',
      );
      final cards = t.widgetList<LocalHangarShipCard>(
        find.byType(LocalHangarShipCard),
      );
      expect(cards.map((c) => c.item.ship.id).toList(), ['a', 'z']);
      await t.tap(find.byKey(const Key('hangar-list')));
      await t.pumpAndSettle();
      final rows = t.widgetList<LocalHangarShipRow>(
        find.byType(LocalHangarShipRow),
      );
      expect(rows.map((r) => r.item.ship.id).toList(), ['a', 'z']);
      expect(port.snapshot.ships.map((s) => s.id).toList(), ['z', 'a']);
      expect(port.saves, 0);
      expect(port.reads, 1);
      expect(t.getSize(find.byKey(const Key('hangar-sort'))).width, 200);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    for (final expanded in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$suite native dimensions expanded=$expanded text=$scale', (
          t,
        ) async {
          await t.pumpWidget(
            scopedApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: expanded ? 200 : null,
                        child: StarBridgeCompactSelect<String>(
                          controlKey: controlKey,
                          identity: 'compact',
                          semanticLabel: '字段',
                          options: options,
                          value: 'a',
                          isExpanded: expanded,
                          onSelected: (_, _) {},
                        ),
                      ),
                      SizedBox(
                        width: expanded ? 200 : null,
                        child: DropdownButton<String>(
                          key: const Key('original'),
                          value: 'a',
                          isExpanded: expanded,
                          items: [
                            for (final option in options)
                              DropdownMenuItem(
                                value: option.value,
                                enabled: option.enabled,
                                child: Text(option.label),
                              ),
                          ],
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          expect(
            t.getSize(find.byKey(controlKey)),
            t.getSize(find.byKey(const Key('original'))),
          );
          expect(t.takeException(), isNull);
        });
      }
    }
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('$suite narrow toolbar dropdown review text 200 percent', (
      t,
    ) async {
      size(t, const Size(400, 700));
      final boundary = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: scopedApp(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('每页'),
                      StarBridgeCompactSelect<int>(
                        identity: 'page',
                        controlKey: controlKey,
                        semanticLabel: '每页',
                        value: 50,
                        options: const [
                          StarBridgeSelectOption(value: 25, label: '25'),
                          StarBridgeSelectOption(value: 50, label: '50'),
                          StarBridgeSelectOption(value: 100, label: '100'),
                        ],
                        onSelected: (_, _) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
            suite,
          ),
        ),
      );
      await t.pumpAndSettle();
      await open(t, controlKey, 'pointer');
      await t.pump(const Duration(milliseconds: 80));
      expect(t.takeException(), isNull);
      await capture(t, boundary, '${suite.name}-200-enter');
      await t.pumpAndSettle();
      await capture(t, boundary, '${suite.name}-200');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
    });
  }
}
