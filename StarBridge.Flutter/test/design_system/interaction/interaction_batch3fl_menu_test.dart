import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_directory.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_navigation.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_sidebar.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_organizations_test.dart' show fixture;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

Map<String, Object?> directoryData({
  bool busy = false,
  bool open = true,
  bool search = true,
  String scope = 'directory-one',
  String query = '',
  String openKey = 'a2',
}) => {
  'state': 'ready',
  'scope': scope,
  'title': '我的组织',
  'busy': busy,
  'buttons': [
    if (search)
      {
        'key': 'a1',
        'label': '搜索组织',
        'role': 'searchOrganizations',
        'input': '搜索已加入的组织',
        'limit': 8,
      },
    {'key': 'a3', 'label': '下一页', 'role': 'nextPage', 'limit': 128},
  ],
  'rows': [
    {
      'title': '远航者组织',
      'detail': '一起探索、护航与远征。',
      'buttons': [
        if (open)
          {
            'key': openKey,
            'label': '打开组织',
            'role': 'openOrganization',
            'limit': 128,
          },
      ],
    },
  ],
  'organization': {
    'tab': 'directory',
    'query': query,
    'total': 1,
    'matched': 1,
    'offset': 0,
    'rows': [
      {
        'memberCount': 24,
        'relationship': 'owner',
        'language': 'zh-CN',
        'tags': '探索,贸易',
        'activeTime': '周末 19:00–23:00',
      },
    ],
  },
};

class MenuProbe {
  MenuProbe(this.suite, this.kind);
  InteractionSuite suite;
  final String kind;
  bool reduce = false, light = false, busy = false, shown = true;
  Map<String, Object?> directory = directoryData();
  Map<String, Object?> navigation = fixture();
  List<MenuOrganizationNavigationItem> items = const [
    MenuOrganizationNavigationItem(
      '第一组织',
      '集合',
      '10:00',
      null,
      'a20',
      125,
      true,
    ),
    MenuOrganizationNavigationItem('第二组织', '暂无消息', '', null, 'a21', 0, false),
  ];
  final commands = <(String, String, InteractionSource)>[];
  late StateSetter update;
  void action(String key, String value) =>
      commands.add((key, value, currentStarBridgeActivationSource));
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        SizedBox(
          width: kind == 'sidebar' ? 280 : 920,
          height: 760,
          child: shown
              ? switch (kind) {
                  'directory' => MenuOrganizationDirectory(
                    view: MenuFeatureView.parse(directory),
                    onAction: action,
                  ),
                  'sidebar' => MenuOrganizationSidebar(
                    items: items,
                    busy: busy,
                    onSelect: (id) => action(id, ''),
                  ),
                  _ => Align(
                    alignment: Alignment.topLeft,
                    child: MenuOrganizationNavigation(
                      view: MenuFeatureView.parse(navigation),
                      onAction: action,
                    ),
                  ),
                }
              : const SizedBox(),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<void> menuFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

FocusNode menuFocus(WidgetTester t, Finder target) {
  final widget = t.widget(target);
  if (widget is ButtonStyleButton) return widget.focusNode!;
  if (widget is ChoiceChip) return widget.focusNode!;
  if (widget is SuitePressable && widget.focusNode != null) {
    return widget.focusNode!;
  }
  final detectors = find
      .descendant(of: target, matching: find.byType(FocusableActionDetector))
      .evaluate()
      .where(
        (e) => identical(
          e.findAncestorWidgetOfExactType<SuitePressable>(),
          widget,
        ),
      )
      .map((e) => (e.widget as FocusableActionDetector).focusNode)
      .whereType<FocusNode>()
      .toList();
  expect(detectors, hasLength(1));
  return detectors.single;
}

Future<void> menuActivate(
  WidgetTester t,
  String key,
  String label,
  String input,
) async {
  final target = find.byKey(ValueKey(key));
  expect(target, findsOneWidget);
  if (input == 'reader') {
    final nodes = exposedNodes(t).where((n) {
      final d = n.getSemanticsData();
      return d.flagsCollection.isButton &&
          d.label.contains(label) &&
          d.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1), reason: 'One exposed action for $label');
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    final node = menuFocus(t, target);
    FocusScope.of(t.element(target)).unfocus();
    await menuFrames(t);
    for (var i = 0; !node.hasPrimaryFocus && i < 35; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await menuFrames(t);
    }
    expect(
      node.hasPrimaryFocus,
      isTrue,
      reason: '$node\n${FocusManager.instance.toStringDeep()}',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final gesture = await t.startGesture(
      // A card center can contain the nested Enter button. Use its identity
      // body when testing the outer gesture, the actual button otherwise.
      key == 'menu-organization-choice-0'
          ? t.getCenter(find.text('远航者组织'))
          : t.getCenter(target),
      kind: ui.PointerDeviceKind.touch,
    );
    await gesture.up();
  }
  await menuFrames(t);
}

void expectMenuCommand(
  MenuProbe p,
  int before,
  String key,
  String payload,
  String input,
) {
  expect(p.commands, hasLength(before + 1), reason: 'No duplicate command');
  expect(p.commands.last, (
    key,
    payload,
    input == 'touch' ? InteractionSource.pointer : InteractionSource.keyboard,
  ));
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['touch', 'keyboard', 'reader']) {
      testWidgets('3fl $suite $input directory nested actions and busy', (
        t,
      ) async {
        size(t, const Size(1200, 900));
        final semantics = t.ensureSemantics();
        final p = MenuProbe(suite, 'directory');
        try {
          await t.pumpWidget(p.app());
          await menuFrames(t);
          expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
          final commands = [
            ('menu-organization-choice-0', '远航者组织', 'a2', ''),
            ('menu-organization-enter-0', '进入组织', 'a2', ''),
            ('menu-organization-refresh', '刷新', 'refresh', ''),
            ('menu-organization-action-a3', '下一页', 'a3', ''),
          ];
          for (final (key, label, command, payload) in commands) {
            final count = p.commands.length;
            await menuActivate(t, key, label, input);
            expectMenuCommand(p, count, command, payload, input);
          }
          await t.enterText(find.byType(TextField), '北辰');
          final count = p.commands.length;
          await menuActivate(t, 'menu-organization-submit-search', '搜索', input);
          expectMenuCommand(p, count, 'a1', '北辰', input);
          p.update(() {
            p.directory = directoryData(busy: true);
            p.reduce = true;
            p.light = true;
          });
          await menuFrames(t);
          expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
          final before = p.commands.length;
          for (final (key, _, _, _) in commands) {
            final target = find.byKey(ValueKey(key));
            await t.tapAt(t.getCenter(target));
          }
          await menuFrames(t);
          expect(p.commands.length, before);
          expect(
            exposedNodes(t).where(
              (n) =>
                  n.getSemanticsData().hasAction(ui.SemanticsAction.tap) &&
                  (n.getSemanticsData().label.contains('进入组织') ||
                      n.getSemanticsData().label.contains('远航者组织')),
            ),
            isEmpty,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      });

      testWidgets('3fl $suite $input sidebar selection stays controlled', (
        t,
      ) async {
        size(t, const Size(1200, 900));
        final semantics = t.ensureSemantics();
        final p = MenuProbe(suite, 'sidebar');
        try {
          await t.pumpWidget(p.app());
          await menuFrames(t);
          final key = 'menu-organization-sidebar-a21';
          await menuActivate(t, key, '第二组织', input);
          expectMenuCommand(p, 0, 'a21', '', input);
          expect(
            t
                .widget<StarBridgeActionRow>(
                  find.ancestor(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(StarBridgeActionRow),
                  ),
                )
                .semanticSelected,
            isFalse,
          );
          for (var i = 0; i < 3; i++) {
            final count = p.commands.length;
            await menuActivate(t, key, '第二组织', input);
            expectMenuCommand(p, count, 'a21', '', input);
          }
          p.update(() {
            p.busy = true;
            p.reduce = true;
            p.light = true;
          });
          await menuFrames(t);
          final before = p.commands.length;
          await t.tapAt(t.getCenter(find.byKey(ValueKey(key))));
          await t.enterText(
            find.byKey(const ValueKey('menu-organization-search')),
            '第二',
          );
          await menuFrames(t);
          expect(find.text('第一组织'), findsNothing);
          expect(find.text('第二组织'), findsOneWidget);
          expect(
            p.commands.length,
            before,
            reason: 'Local filtering remains enabled while commands are busy',
          );
          expect(
            exposedNodes(t).where(
              (n) =>
                  n.getSemanticsData().label.contains('第二组织') &&
                  n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            ),
            isEmpty,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      });

      testWidgets('3fl $suite $input navigation selected and refresh', (
        t,
      ) async {
        size(t, const Size(1200, 900));
        final semantics = t.ensureSemantics();
        final p = MenuProbe(suite, 'navigation');
        try {
          await t.pumpWidget(p.app());
          await menuFrames(t);
          await menuActivate(t, 'community-section-members', '成员', input);
          expect(
            p.commands,
            isEmpty,
            reason: 'Re-select confirmed tab does not dispatch',
          );
          await menuActivate(t, 'community-section-ships', '舰船', input);
          expectMenuCommand(p, 0, 'a3', '', input);
          await menuActivate(t, 'menu-organization-tab-refresh', '刷新', input);
          expectMenuCommand(p, 1, 'refresh', '', input);
          p.update(() {
            p.navigation = fixture()..['busy'] = true;
            p.reduce = true;
            p.light = true;
          });
          await menuFrames(t);
          final before = p.commands.length;
          await t.tapAt(
            t.getCenter(
              find.byKey(const ValueKey('menu-organization-tab-refresh')),
            ),
          );
          await t.tapAt(
            t.getCenter(find.byKey(const ValueKey('community-section-ships'))),
          );
          await menuFrames(t);
          expect(p.commands.length, before);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      });
    }

    testWidgets('3fl $suite native search draft IME and scope replacement', (
      t,
    ) async {
      size(t, const Size(1200, 900));
      final p = MenuProbe(suite, 'directory');
      await t.pumpWidget(p.app());
      await menuFrames(t);
      final field = find.byType(TextField);
      final controller = t.widget<TextField>(field).controller!;
      await t.showKeyboard(field);
      const composing = TextEditingValue(
        text: '远航bei',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 5),
      );
      t.testTextInput.updateEditingValue(composing);
      await menuFrames(t);
      expect(controller.value, composing);
      p.update(() {
        p.directory = directoryData(query: '服务端旧值', openKey: 'a9');
        p.suite = suite == InteractionSuite.rail
            ? InteractionSuite.glow
            : InteractionSuite.rail;
        p.reduce = true;
        p.light = true;
      });
      await menuFrames(t);
      expect(t.widget<TextField>(field).controller, same(controller));
      expect(controller.value, composing);
      expect(p.commands, isEmpty);
      // A response can renew opaque action keys without overwriting this draft.
      await menuActivate(t, 'menu-organization-enter-0', '进入组织', 'touch');
      expectMenuCommand(p, 0, 'a9', '', 'touch');
      await t.enterText(field, '123456789012');
      expect(controller.text, '12345678');
      await t.testTextInput.receiveAction(TextInputAction.done);
      expect(p.commands.last, ('a1', '12345678', InteractionSource.keyboard));
      p.update(
        () => p.directory = directoryData(scope: 'directory-two', query: '新组织'),
      );
      await menuFrames(t);
      expect(t.widget<TextField>(field).controller, same(controller));
      expect(controller.text, '新组织');
      expect(controller.value.composing, TextRange.empty);
      expect(p.commands.length, 2);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('3fl $suite absent open/search and null section remain inert', (
      t,
    ) async {
      size(t, const Size(1200, 900));
      final semantics = t.ensureSemantics();
      final p = MenuProbe(suite, 'directory');
      p.directory = directoryData(open: false, search: false);
      try {
        await t.pumpWidget(p.app());
        await menuFrames(t);
        expect(find.byType(TextField), findsNothing);
        await t.tapAt(t.getCenter(find.text('远航者组织')));
        await t.tapAt(
          t.getCenter(find.byKey(const ValueKey('menu-organization-enter-0'))),
        );
        expect(p.commands, isEmpty);
        expect(
          exposedNodes(t).where(
            (n) =>
                n.getSemanticsData().label.contains('进入组织') &&
                n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          ),
          isEmpty,
        );
        final nav = MenuProbe(suite, 'navigation');
        (nav.navigation['organization'] as Map)['sections'] = {
          'members': 'a2',
          'ships': null,
          'chat': 'a5',
        };
        await t.pumpWidget(nav.app());
        await menuFrames(t);
        final before = nav.commands.length;
        await t.tapAt(
          t.getCenter(find.byKey(const ValueKey('community-section-chat'))),
        );
        expect(
          nav.commands.length,
          before,
          reason: 'Original any-null section disables whole section group',
        );
        await menuActivate(t, 'menu-organization-tab-refresh', '刷新', 'reader');
        expectMenuCommand(nav, 0, 'refresh', '', 'reader');
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        semantics.dispose();
      }
    });

    testWidgets('3fl $suite sidebar local draft and renewed selection', (
      t,
    ) async {
      size(t, const Size(1200, 900));
      final p = MenuProbe(suite, 'sidebar');
      await t.pumpWidget(p.app());
      await menuFrames(t);
      final field = find.byKey(const ValueKey('menu-organization-search'));
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      await t.enterText(field, '第二');
      await menuFrames(t);
      final controller = t.widget<EditableText>(editable).controller;
      p.update(() {
        p.items = const [
          MenuOrganizationNavigationItem(
            '第二组织',
            '已更新',
            '11:00',
            null,
            'a30',
            2,
            true,
          ),
          MenuOrganizationNavigationItem(
            '第三组织',
            '暂无消息',
            '',
            null,
            'a31',
            0,
            false,
          ),
        ];
        p.light = true;
        p.reduce = true;
        p.suite = suite == InteractionSuite.scan
            ? InteractionSuite.glow
            : InteractionSuite.scan;
      });
      await menuFrames(t);
      expect(t.widget<EditableText>(editable).controller, same(controller));
      expect(controller.text, '第二');
      expect(find.text('第三组织'), findsNothing);
      final action = t.widget<StarBridgeActionRow>(
        find.ancestor(
          of: find.byKey(const ValueKey('menu-organization-sidebar-a30')),
          matching: find.byType(StarBridgeActionRow),
        ),
      );
      expect(action.semanticSelected, isTrue);
      await menuActivate(t, 'menu-organization-sidebar-a30', '第二组织', 'touch');
      expectMenuCommand(p, 0, 'a30', '', 'touch');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('3fl $suite card geometry retains panel/logo/padding', (
      t,
    ) async {
      size(t, const Size(1200, 900));
      final p = MenuProbe(suite, 'directory');
      await t.pumpWidget(p.app());
      await menuFrames(t);
      final target = find.byKey(const ValueKey('menu-organization-choice-0'));
      final outer = t.widget<Material>(
        find.ancestor(of: target, matching: find.byType(Material)).first,
      );
      final context = t.element(target);
      expect(outer.color, context.tokens.surfaces.panel.fill);
      expect(
        (outer.shape as RoundedRectangleBorder).side.color,
        context.tokens.surfaces.panel.border,
      );
      final body = find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is Padding && w.padding == const EdgeInsets.all(16),
        ),
      );
      expect(body, findsOneWidget);
      final title = find.text('远航者组织');
      final card = t.getRect(target);
      expect(card.width, (920 - 32 - 12) / 2);
      expect(t.getTopLeft(title).dx - card.left, 16 + 48 + 12);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
