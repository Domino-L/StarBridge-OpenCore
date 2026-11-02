import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_navigation.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_navigation.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/communities/community_section_navigation.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/party_rooms/room_workspace_layout.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app, pixels;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3e_test.dart' show workspaceApp;
import '../../features/friends/social_layout_test.dart' show size, loadFonts;
import '../../app/menu_overlay/menu_organizations_test.dart' show fixture;

class ChoicesHarness extends StatefulWidget {
  const ChoicesHarness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<ChoicesHarness> createState() => ChoicesState();
}

class ChoicesState extends State<ChoicesHarness> {
  late var suite = widget.suite;
  var selected = 'members', enabled = true, reduce = false;
  var unread = 0, width = 500.0;
  var sections = <String, bool>{
    'members': true,
    'chat': true,
    'ships': true,
    'broadcast': false,
  };
  final calls = <String>[];
  Completer<bool>? guard;
  final boundary = GlobalKey();
  void change(VoidCallback update) => setState(update);
  Future<void> request(String id) async {
    calls.add(id);
    final result = guard;
    if (result != null && !await result.future) return;
    if (mounted) setState(() => selected = id);
  }

  @override
  Widget build(BuildContext context) => app(
    RepaintBoundary(
      key: boundary,
      child: SizedBox(
        width: width,
        child: CommunitySectionNavigation(
          sections: sections,
          selected: selected,
          enabled: enabled,
          chatUnreadCount: unread,
          onSelected: (id) => unawaited(request(id)),
        ),
      ),
    ),
    suite: suite,
    reduce: reduce,
  );
}

Finder tab(String id) => find.byKey(ValueKey('community-section-$id'));
SuiteSelectionTrackState track(WidgetTester t) =>
    t.state<SuiteSelectionTrackState>(find.byType(SuiteSelectionTrack));
FocusNode focus(WidgetTester t, String id) {
  final widget = t.widget(tab(id));
  return widget is ChoiceChip
      ? widget.focusNode!
      : (widget as SuitePressable).focusNode!;
}

Future<ChoicesState> mount(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<ChoicesState>();
  await t.pumpWidget(ChoicesHarness(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3F'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final folder = Directory('build/reviews/interaction-batch3f');
      await folder.create(recursive: true);
      await File('${folder.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite deferred owner holds selection until confirmed, cancelled stays put',
      (t) async {
        final h = await mount(t, suite);
        h.guard = Completer<bool>();
        await t.tap(tab('chat'));
        await t.pump(const Duration(milliseconds: 200));
        expect(h.selected, 'members');
        expect(track(t).indicatorRect, track(t).itemRect(0));
        h.guard!.complete(false);
        await t.pumpAndSettle();
        expect(h.selected, 'members');
        h.guard = Completer<bool>();
        focus(t, 'chat').requestFocus();
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        h.guard!.complete(true);
        await t.pump();
        await t.pump();
        expect(h.selected, 'chat');
        expect(track(t).indicatorRect, track(t).itemRect(1));
        expect(
          track(t).isStretching || track(t).isSweeping || track(t).isRinging,
          false,
        );
        expect(h.calls, ['chat', 'chat']);
      },
    );

    testWidgets(
      '$suite rapid reversals and current-tab presses keep active feedback',
      (t) async {
        final h = await mount(t, suite);
        final idle = await pixels(t, h.boundary);
        await t.tap(tab('members'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(await pixels(t, h.boundary), isNot(idle));
        for (final id in ['chat', 'ships', 'chat', 'members']) {
          await t.tap(tab(id));
          await t.pump(const Duration(milliseconds: 20));
        }
        await t.pumpAndSettle();
        expect(h.calls, ['members', 'chat', 'ships', 'chat', 'members']);
        expect(track(t).indicatorRect, track(t).itemRect(0));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite keyboard skips disabled items; unread has one reader label',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final h = await mount(t, suite);
          h.change(() => h.unread = 23);
          await t.pumpAndSettle();
          focus(t, 'ships').requestFocus();
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await t.pump();
          await t.pump();
          expect(h.selected, 'members');
          expect(focus(t, 'members').hasFocus, isTrue);
          final choice = t.widget<StarBridgeChoiceNavigation>(
            find.byType(StarBridgeChoiceNavigation),
          );
          final label = choice.choices.singleWhere((c) => c.id == 'chat').label;
          final nodes = exposedNodes(t)
              .where((n) => n.getSemanticsData().label == label)
              .toList();
          expect(nodes, hasLength(1));
          t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
            nodes.single.id,
            SemanticsAction.tap,
          );
          await t.pump();
          await t.pump();
          expect(h.selected, 'chat');
          expect(track(t).indicatorRect, track(t).itemRect(1));
          final disabledLabel = choice.choices
              .singleWhere((c) => c.id == 'broadcast')
              .label;
          final disabled = exposedNodes(t)
              .where((n) => n.getSemanticsData().label == disabledLabel)
              .single;
          expect(
            disabled.getSemanticsData().hasAction(SemanticsAction.tap),
            false,
          );
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '$suite live disable, unread resize and theme keep identity and no commands',
      (t) async {
        final h = await mount(t, suite);
        final chatFocus = focus(t, 'chat');
        await t.tap(tab('chat'));
        await t.pumpAndSettle();
        final original = track(t).itemRect(1)!;
        h.change(() {
          h.unread = 321;
          h.enabled = false;
        });
        await t.pumpAndSettle();
        expect(track(t).itemRect(1)!.width, greaterThan(original.width));
        expect(track(t).indicatorRect, track(t).itemRect(1));
        await t.tap(tab('chat'), warnIfMissed: false);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
        expect(h.calls, ['chat']);
        h.change(() {
          h.enabled = true;
          h.suite = InteractionSuite.glow;
        });
        await t.pumpAndSettle();
        expect(focus(t, 'chat'), same(chatFocus));
        expect(h.calls, ['chat']);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite reordered stable ids preserve focus and removed/empty selected hides marker',
      (t) async {
        final h = await mount(t, suite);
        final node = focus(t, 'members');
        node.requestFocus();
        await t.pumpAndSettle();
        h.change(
          () =>
              h.sections = {'chat': true, 'members': true, 'broadcast': false},
        );
        await t.pumpAndSettle();
        expect(focus(t, 'members'), same(node));
        expect(node.hasFocus, isTrue);
        expect(track(t).indicatorRect, track(t).itemRect(1));
        h.change(() => h.sections = {'chat': true});
        await t.pumpAndSettle();
        expect(track(t).indicatorRect, isNull);
        h.change(() => h.sections = {});
        await t.pumpAndSettle();
        expect(track(t).indicatorRect, isNull);
        expect(h.calls, isEmpty);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite keyboard scroll reveal and live reduced motion land without queue',
      (t) async {
        final h = await mount(t, suite);
        h.change(() => h.width = 150);
        await t.pumpAndSettle();
        focus(t, 'members').requestFocus();
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        await t.pump();
        expect(h.selected, 'chat');
        expect(
          t.getRect(tab('chat')).right,
          lessThanOrEqualTo(
            t.getRect(find.byType(SingleChildScrollView)).right + 1,
          ),
        );
        await t.tap(tab('members'), warnIfMissed: false);
        h.change(() => h.reduce = true);
        await t.pump();
        await t.pump();
        expect(
          track(t).indicatorRect,
          track(t).itemRect(h.selected == 'members' ? 0 : 1),
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, false);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite real community leave guard cancels then explicitly discards chat draft',
      (t) async {
        size(t, const Size(1200, 900));
        final port = ExampleCommunities();
        addTearDown(port.close);
        final frame = GlobalKey();
        await t.pumpWidget(
          workspaceApp(
            RepaintBoundary(
              key: frame,
              child: CommunityWorkspaceView(
                port: port,
                targetRef: '00000000000000000000000000000002',
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await capture(t, frame, '${suite.name}-community');
        await t.tap(tab('chat'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        await capture(t, frame, '${suite.name}-community-switch');
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('community-chat-input')),
          '保留草稿',
        );
        await t.pumpAndSettle();
        await t.tap(tab('members'));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(CommunityChatPanel), findsOneWidget);
        expect(track(t).indicatorRect, track(t).itemRect(1));
        await t.tap(find.widgetWithText(StarBridgeActionButton, '继续编辑'));
        await t.pumpAndSettle();
        expect(find.text('保留草稿'), findsOneWidget);
        final chat = t.state<CommunityChatPanelState>(
          find.byType(CommunityChatPanel),
        );
        await t.tap(tab('members'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(StarBridgeActionButton, '丢弃草稿并返回'));
        await t.pumpAndSettle();
        expect(chat.model.draft, isEmpty);
        expect(track(t).indicatorRect, track(t).itemRect(0));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$suite real menu emits authorized scoped command only and waits for projection',
      (t) async {
        final actions = <String>[];
        final view = MenuFeatureView.parse(fixture());
        await t.pumpWidget(
          workspaceApp(
            SizedBox(
              width: 500,
              child: MenuOrganizationNavigation(
                view: view,
                onAction: (key, _) => actions.add(key),
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(tab('chat'));
        await t.pumpAndSettle();
        expect(actions, ['a5']);
        expect(track(t).indicatorRect, track(t).itemRect(0));
        await t.tap(tab('members'));
        await t.pumpAndSettle();
        expect(actions, ['a5']);
        final refreshed = fixture();
        (refreshed['organization'] as Map)['sections'] = {
          'members': null,
          'chat': null,
          'ships': null,
          'announcements': null,
        };
        await t.pumpWidget(
          workspaceApp(
            SizedBox(
              width: 500,
              child: MenuOrganizationNavigation(
                view: MenuFeatureView.parse(refreshed),
                onAction: (key, _) => actions.add(key),
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(tab('chat'), warnIfMissed: false);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pumpAndSettle();
        expect(actions, ['a5']);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite real room compact panes retain chat state through tabs and breakpoint',
      (t) async {
        size(t, const Size(640, 700));
        final controller = TextEditingController();
        final page = RoomWorkspaceLayout(
          compactTabs: true,
          members: const Text('Members pane'),
          chat: TextField(key: const Key('draft'), controller: controller),
        );
        await t.pumpWidget(workspaceApp(page, suite));
        await t.pumpAndSettle();
        await t.tap(tab('chat'));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('draft')), '房间草稿');
        await t.tap(tab('members'));
        await t.pumpAndSettle();
        t.view.physicalSize = const Size(1200, 700);
        await t.pumpAndSettle();
        expect(controller.text, '房间草稿');
        t.view.physicalSize = const Size(640, 700);
        await t.pumpAndSettle();
        await t.tap(tab('chat'));
        await t.pumpAndSettle();
        expect(find.text('房间草稿'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'custom target geometry equals original native chips including unread and disabled',
    (t) async {
      final h = await mount(t, InteractionSuite.standard);
      h.change(() => h.unread = 23);
      await t.pumpAndSettle();
      final sizes = {for (final id in h.sections.keys) id: t.getSize(tab(id))};
      for (final suite in InteractionSuite.values) {
        h.change(() => h.suite = suite);
        await t.pumpAndSettle();
        for (final id in h.sections.keys) {
          expect(t.getSize(tab(id)), sizes[id]);
        }
      }
      expect(t.takeException(), isNull);
    },
  );
}
