import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_controls.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_toolbar.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/direct_messages/direct_message_send_test.dart' as direct;

const chipKey = Key('chip');

class ChipHarness extends StatefulWidget {
  const ChipHarness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<ChipHarness> createState() => ChipState();
}

class ChipState extends State<ChipHarness> {
  late var suite = widget.suite;
  bool selected = false,
      enabled = true,
      apply = false,
      reduce = false,
      light = false;
  final requests = <bool>[];
  final sources = <InteractionSource>[];
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    Center(
      child: StarBridgeChoiceChip(
        controlKey: chipKey,
        label: '筛选',
        selected: selected,
        onSelected: enabled
            ? (value) {
                requests.add(value);
                sources.add(currentStarBridgeActivationSource);
                if (apply) setState(() => selected = value);
              }
            : null,
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<ChipState> harness(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<ChipState>();
  await t.pumpWidget(ChipHarness(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

Future<void> keyActivate(
  WidgetTester t,
  Finder target,
  LogicalKeyboardKey key,
) async {
  final native = find.descendant(of: target, matching: find.byType(ChoiceChip));
  if (native.evaluate().isNotEmpty || t.widget(target) is ChoiceChip) {
    t
        .widget<ChoiceChip>(native.evaluate().isEmpty ? target : native)
        .focusNode!
        .requestFocus();
  } else {
    t.widget<SuiteChoiceChip>(target).focusNode!.requestFocus();
  }
  await t.pumpAndSettle();
  await t.sendKeyEvent(key);
  await t.pump();
  await t.pump();
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

class Inbox extends NotificationInboxController {
  Inbox() : super(null) {
    ready = true;
    items = [
      InboxItem(
        'a' * 32,
        'system',
        'normal',
        '普通通知',
        '内容',
        DateTime(2026),
        false,
        '',
        '',
        true,
      ),
      InboxItem(
        'b' * 32,
        'fleet',
        'action_required',
        '待处理通知',
        '内容',
        DateTime(2026),
        false,
        '',
        '',
        true,
      ),
    ];
  }
  @override
  Future<bool> refresh({bool quiet = false, bool reuseFresh = false}) async =>
      true;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite controlled chip does not select before owner commits', (
      t,
    ) async {
      final state = await harness(t, suite);
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byKey(chipKey));
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(state.requests, [true, true, true]);
      expect(state.sources, everyElement(InteractionSource.pointer));
      expect(
        t
            .widget<StarBridgeChoiceChip>(find.byType(StarBridgeChoiceChip))
            .selected,
        isFalse,
      );
      expect(t.hasRunningAnimations, isTrue);
      state.change(() => state.selected = true);
      await t.pumpAndSettle();
      await t.tap(find.byKey(chipKey));
      expect(state.requests.last, isFalse);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets(
        '$suite $key immediate selection and no decorated animation',
        (t) async {
          final state = await harness(t, suite);
          state.change(() => state.apply = true);
          await t.pump();
          await keyActivate(t, find.byKey(chipKey), key);
          expect(state.sources, [InteractionSource.keyboard]);
          expect(state.selected, isTrue);
          expect(t.hasRunningAnimations, isFalse);
          await t.pump(const Duration(seconds: 1));
          expect(state.requests, hasLength(1));
        },
      );
    }
    testWidgets('$suite reader single node plus disabled gate', (t) async {
      final semantics = t.ensureSemantics();
      final state = await harness(t, suite);
      state.change(() => state.apply = true);
      await t.pump();
      reader(t, '筛选');
      await t.pump();
      await t.pump();
      expect(state.sources, [InteractionSource.keyboard]);
      expect(state.selected, isTrue);
      expect(t.hasRunningAnimations, isFalse);
      state.change(() => state.enabled = false);
      await t.pumpAndSettle();
      final nodes = exposedNodes(t)
          .where((n) => n.getSemanticsData().label == '筛选')
          .toList();
      expect(nodes, hasLength(1));
      expect(
        nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      await t.tap(find.byKey(chipKey), warnIfMissed: false);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(state.requests, hasLength(1));
      expect(t.takeException(), isNull);
      semantics.dispose();
    });
    testWidgets(
      '$suite pointer then live reduce clears feedback and preserves owner',
      (t) async {
        final state = await harness(t, suite);
        state.change(() => state.apply = true);
        await t.pump();
        await t.tap(find.byKey(chipKey));
        await t.pump(const Duration(milliseconds: 40));
        expect(state.selected, isTrue);
        state.change(() {
          state.reduce = true;
        });
        await t.pump();
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        expect(state.selected, isTrue);
        await t.tap(find.byKey(chipKey));
        await t.pump();
        await t.pump();
        expect(state.selected, isFalse);
        expect(state.requests, [true, false]);
        expect(t.hasRunningAnimations, isFalse);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite switching suites does not change owner selection/callbacks',
      (t) async {
        final state = await harness(t, suite);
        state.change(() {
          state.selected = true;
          state.light = true;
        });
        await t.pumpAndSettle();
        for (final next in InteractionSuite.values) {
          state.change(() => state.suite = next);
          await t.pumpAndSettle();
          expect(state.selected, isTrue);
          expect(state.requests, isEmpty);
          expect(find.text('筛选'), findsOneWidget);
          expect(t.takeException(), isNull);
        }
      },
    );
    testWidgets(
      '$suite rapid reversal retains every active choice and settles',
      (t) async {
        final state = await harness(t, suite);
        state.change(() => state.apply = true);
        await t.pump();
        for (var i = 0; i < 4; i++) {
          await t.tap(find.byKey(chipKey));
          await t.pump(const Duration(milliseconds: 50));
          expect(t.hasRunningAnimations, isTrue);
        }
        expect(state.requests, [true, false, true, false]);
        expect(state.sources, everyElement(InteractionSource.pointer));
        expect(state.selected, isFalse);
        await t.pumpAndSettle();
        expect(t.hasRunningAnimations, isFalse);
        expect(state.requests, hasLength(4));
      },
    );
    testWidgets(
      '$suite disable during press retires feedback and denies activation',
      (t) async {
        final state = await harness(t, suite);
        await t.tap(find.byKey(chipKey));
        await t.pump(const Duration(milliseconds: 40));
        state.change(() => state.enabled = false);
        await t.pump();
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        await t.tap(find.byKey(chipKey), warnIfMissed: false);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(state.requests, [true]);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite fleet member filter retains original scoped module', (
      t,
    ) async {
      size(t, const Size(1200, 800));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final module = createOfficialFleetMembersModule(
        InMemoryOfficialFleetMembersAdapter.forReview(),
      );
      addTearDown(module.dispose);
      await module.open('officialFleet:7');
      await t.pumpWidget(
        scopedApp(
          ValueListenableBuilder(
            valueListenable: module.projection,
            builder: (_, p, _) => OfficialFleetMembersToolbar(
              projection: p,
              module: module,
              searchController: controller,
            ),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      await keyActivate(
        t,
        find.byKey(const Key('official-fleet-members-filter-inGame')),
        LogicalKeyboardKey.enter,
      );
      await t.pumpAndSettle();
      expect(
        module.projection.value.query!.filter,
        OfficialFleetMemberFilter.inGame,
      );
      expect(
        module.projection.value.members.every(
          (m) => m.presence == OfficialFleetMemberPresence.inGame,
        ),
        isTrue,
      );
      await t.tap(find.byKey(const Key('official-fleet-members-filter-all')));
      await t.pumpAndSettle();
      expect(
        module.projection.value.query!.filter,
        OfficialFleetMemberFilter.all,
      );
      expect(module.projection.value.members.length, greaterThan(1));
      expect(t.takeException(), isNull);
    });
    testWidgets('$suite fleet ship filter retains original scoped module', (
      t,
    ) async {
      size(t, const Size(1200, 800));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
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
      await t.tap(
        find.byKey(const Key('official-fleet-ships-filter-requestable')),
      );
      await t.pumpAndSettle();
      expect(
        module.projection.value.query!.filter,
        OfficialFleetShipFilter.requestable,
      );
      await keyActivate(
        t,
        find.byKey(const Key('official-fleet-ships-filter-all')),
        LogicalKeyboardKey.space,
      );
      await t.pumpAndSettle();
      expect(
        module.projection.value.query!.filter,
        OfficialFleetShipFilter.all,
      );
      expect(module.projection.value.ships, hasLength(6));
      expect(t.takeException(), isNull);
    });
    testWidgets('$suite notifications local filter without new writes', (
      t,
    ) async {
      size(t, const Size(1200, 850));
      final inbox = Inbox();
      addTearDown(inbox.dispose);
      await t.pumpWidget(
        scopedApp(NotificationInboxPage(controller: inbox), suite),
      );
      await t.pumpAndSettle();
      expect(find.text('普通通知'), findsOneWidget);
      await t.tap(find.byKey(const Key('notification-filter-action')));
      await t.pumpAndSettle();
      expect(find.text('普通通知'), findsNothing);
      expect(find.text('待处理通知'), findsOneWidget);
      await keyActivate(
        t,
        find.byKey(const Key('notification-filter-all')),
        LogicalKeyboardKey.enter,
      );
      await t.pumpAndSettle();
      expect(find.text('普通通知'), findsOneWidget);
      expect(inbox.items, hasLength(2));
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    testWidgets(
      '$suite direct group switch retains cancel/discard draft guard',
      (t) async {
        size(t, const Size(1200, 900));
        final port = direct.Sender();
        final module = await direct.opened(port);
        addTearDown(module.dispose);
        module.editDraft('必须保留的草稿');
        await t.pumpWidget(
          scopedApp(
            DirectMessagesPage(
              createPort: () => port,
              sharedModule: module,
              onBack: () {},
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        final target = find.byKey(const Key('direct-messages-filter-true'));
        await keyActivate(t, target, LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(module.requests, isFalse);
        expect(module.draft, '必须保留的草稿');
        // Retain the original dialog and business choice, not a presentation
        // layer's optimistic selection or automatic discard.
        await t.tap(find.byKey(const ValueKey('chat-leave-keep')));
        await t.pumpAndSettle();
        expect(module.requests, isFalse);
        expect(module.draft, '必须保留的草稿');
        await t.tap(target);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('chat-leave-discard')));
        await t.pumpAndSettle();
        expect(module.requests, isTrue);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('standard chip preserves original native dimensions', (t) async {
    await t.pumpWidget(
      scopedApp(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StarBridgeChoiceChip(
              controlKey: chipKey,
              label: '原尺寸',
              selected: true,
              onSelected: (_) {},
            ),
            ChoiceChip(
              key: const Key('original'),
              label: const Text('原尺寸'),
              selected: true,
              onSelected: (_) {},
            ),
          ],
        ),
        InteractionSuite.standard,
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byKey(chipKey)),
      t.getSize(find.byKey(const Key('original'))),
    );
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('four-suite chip review text scale $scale', (t) async {
      size(t, const Size(900, 500));
      final boundary = GlobalKey();
      await t.pumpWidget(
        scopedApp(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: boundary,
              child: Column(
                children: [
                  for (final suite in InteractionSuite.values)
                    StarBridgeInteractionConfiguration(
                      suite: suite,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(suite.name),
                            StarBridgeChoiceChip(
                              label: '已选择',
                              selected: true,
                              onSelected: (_) {},
                            ),
                            StarBridgeChoiceChip(
                              label: '未选择',
                              selected: false,
                              onSelected: (_) {},
                            ),
                            const StarBridgeChoiceChip(
                              label: '不可用',
                              selected: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          InteractionSuite.standard,
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final directory = Directory('build/reviews/interaction-batch3z');
          await directory.create(recursive: true);
          await File('${directory.path}/chips-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    });
  }
}
