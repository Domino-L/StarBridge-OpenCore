import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';

import '../../app/menu_overlay/menu_comms_maturity_test.dart' show fixture;
import '../../app/menu_overlay/menu_comms_list_layout_test.dart'
    show organization;
import 'interaction_batch3ca_test.dart' as base;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ck_test.dart' show mount;
import 'interaction_batch3aa_test.dart' show reader;

Future<void> fire(WidgetTester t, String source, Finder target) async {
  final widget = t.widget(target);
  if (source == 'reader' && widget is MenuAvatarActions) {
    // Select the real exposed avatar node, not the surrounding row's render
    // semantics returned for a non-rendering composition widget.
    reader(t, '${widget.name} · 头像菜单');
    return;
  }
  final isRow = widget is StarBridgeActionRow || widget is SuitePressable;
  if (source != 'keyboard' || !isRow) {
    await base.fire(t, source, target);
    return;
  }
  // Focus the row's actual node, not an arbitrary nested avatar/ListTile.
  final ink = find.descendant(of: target, matching: find.byType(InkWell));
  final detector = find.descendant(
    of: target,
    matching: find.byType(FocusableActionDetector),
  );
  final focus = detector.evaluate().isNotEmpty
      ? t.widget<FocusableActionDetector>(detector.first).focusNode
      : t.widget<InkWell>(ink.first).focusNode;
  expect(focus, isNotNull);
  focus!.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
}

Finder button(String label) => find.byWidgetPredicate(
  (w) => w is StarBridgeActionButton && w.semanticLabel == label,
);
Future<void> press(WidgetTester t, String source, String label) async {
  await fire(t, source, button(label));
  await frames(t);
}

InteractionSource origin(String source) => source == 'pointer'
    ? InteractionSource.pointer
    : InteractionSource.keyboard;
MenuCommsView history({
  bool busy = false,
  bool older = false,
  String notice = '',
  int count = 1,
}) => MenuCommsView(
  'ready',
  name: 'Peer',
  profileKey: 'c1',
  pageKey: 'c1/0',
  hasOlder: true,
  olderPage: older,
  inviteAvailable: true,
  canSend: true,
  notice: notice,
  busy: busy,
  messages: [
    for (var i = 0; i < count; i++)
      (
        incoming: true,
        text: '消息$i · 内容' * 3,
        time: DateTime.utc(2026),
        attachment: i == 0,
      ),
  ],
  attachmentKeys: const {0: 'i7'},
);
Finder organizationRow() => find.ancestor(
  of: find.byKey(const ValueKey('menu-organization-conversation-远航者组织')),
  matching: find.byType(StarBridgeActionRow),
);

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source new-message bottom action changes only the existing scroll owner',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await mount(t, suite);
            h.change(() => h.view = history(count: 40));
            await frames(t);
            final list = find.byKey(const ValueKey('menu-message-history'));
            final scroll = t.widget<ListView>(list).controller!;
            scroll.jumpTo(300);
            await t.pump();
            h.change(() => h.view = history(count: 41));
            await frames(t);
            expect(scroll.offset, greaterThan(48));
            await press(t, source, '有新消息 · 回到底部');
            expect(scroll.offset, 0);
            expect(button('有新消息 · 回到底部'), findsNothing);
            expect(h.calls, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            semantics.dispose();
          }
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source full direct history command variants preserve exact payload and origin',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await mount(t, suite);
            h.change(() => h.view = history());
            await frames(t);
            for (final label in [
              '返回会话列表',
              '较早消息',
              '刷新消息',
              '邀请加入组织',
              '查看组织邀请',
            ]) {
              await press(t, source, label);
            }
            h.change(() => h.view = history(older: true));
            await frames(t);
            await press(t, source, '最新消息');
            h.change(() => h.view = history(notice: '读取失败，保留原消息'));
            await frames(t);
            await press(t, source, '重新读取');
            expect(h.calls, [
              for (final item in [
                ('back', ''),
                ('older', ''),
                ('latest', ''),
                ('inviteSend', ''),
                ('attachment', 'i7'),
                ('latest', ''),
                ('retry', ''),
              ])
                (item.$1, item.$2, origin(source)),
            ]);
            expect(
              t.widget<StarBridgeActionButton>(button('查看组织邀请')).onActivate,
              isNull,
            );
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source actual directory filter, private selection and refresh retain local rules',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await mount(t, suite);
            await press(t, source, '未读');
            expect(
              find.byKey(const ValueKey('menu-conversation-c1')),
              findsNothing,
            );
            await fire(
              t,
              source,
              find.byKey(const ValueKey('menu-conversation-c2')),
            );
            await frames(t);
            await press(t, source, '消息请求');
            expect(
              find.byKey(const ValueKey('menu-conversation-c2')),
              findsNothing,
            );
            await fire(
              t,
              source,
              find.byKey(const ValueKey('menu-conversation-c3')),
            );
            await frames(t);
            await press(t, source, '全部');
            await press(t, source, '刷新');
            expect(h.calls, [
              ('select', 'c2', origin(source)),
              ('select', 'c3', origin(source)),
              ('retry', '', origin(source)),
            ]);
            expect(h.kinds, ['private', 'private']);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source nested avatar is independent from private row selection',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await mount(t, suite);
            final avatar = find.byWidgetPredicate(
              (w) => w is MenuAvatarActions && w.name == '北辰',
            );
            await fire(t, source, avatar);
            await frames(t);
            expect(find.text('查看个人页面'), findsOneWidget);
            expect(h.calls, isEmpty);
            final entry = find.text('查看个人页面');
            await fire(t, source, entry);
            await frames(t);
            expect(h.calls, [('profile', 'c1', origin(source))]);
            expect(h.kinds, isEmpty);
            await fire(
              t,
              source,
              find.byKey(const ValueKey('menu-conversation-c1')),
            );
            await frames(t);
            expect(h.calls.last, ('select', 'c1', origin(source)));
            expect(h.calls, hasLength(2));
            expect(find.text('查看个人页面'), findsNothing);
            expect(h.kinds, ['private']);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source panel failure, records, flow return and close are distinct commands',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await mount(t, suite);
            h.change(() {
              h.embedded = false;
              h.view = const MenuCommsView('restricted');
            });
            await frames(t);
            await press(t, source, '重新读取');
            await press(t, source, '返回会话列表');
            await press(t, source, '关闭');
            expect(h.closes, 1);
            h.change(
              () =>
                  h.view = const MenuCommsView('ready', inviteAvailable: true),
            );
            await frames(t);
            await press(t, source, '邀请发送记录');
            h.change(
              () => h.view = const MenuCommsView(
                'ready',
                invitation: MenuFeatureView(
                  'ready',
                  scope: 'invite1',
                  title: '组织邀请',
                ),
              ),
            );
            await frames(t);
            await press(t, source, '返回通讯');
            expect(h.calls, [
              for (final a in ['retry', 'back', 'inviteRecords', 'inviteClose'])
                (a, '', origin(source)),
            ]);
            expect(h.kinds, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source optional organization component paths keep independent namespace and availability',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await mount(t, suite);
            final initial = organization();
            h.change(
              () => h.org = MenuFeatureView(
                'ready',
                scope: initial.scope,
                channels: initial.channels,
                buttons: [
                  for (final (i, label) in [
                    '下一页',
                    '首页',
                    '更多组织会话',
                    '组织会话首页',
                  ].indexed)
                    (
                      key: 'a${i + 20}',
                      label: label,
                      confirm: null,
                      input: null,
                      role: [
                        'nextPage',
                        'firstPage',
                        'moreOrganizationChats',
                        'organizationChatsHome',
                      ][i],
                      secret: false,
                      limit: 128,
                    ),
                ],
              ),
            );
            await frames(t);
            await fire(t, source, organizationRow());
            await frames(t);
            for (final label in ['下一页', '首页', '更多组织会话', '组织会话首页']) {
              await press(t, source, label);
            }
            h.change(() => h.view = const MenuCommsView('restricted'));
            await frames(t);
            await fire(t, source, organizationRow());
            await frames(t);
            h.change(
              () => h.org = const MenuFeatureView('unavailable', scope: 's1'),
            );
            await frames(t);
            await press(t, source, '组织会话加载失败 · 重试');
            expect(h.calls, [
              ('org:a8', '', origin(source)),
              for (var i = 20; i < 24; i++) ('org:a$i', '', origin(source)),
              ('org:a8', '', origin(source)),
              ('org:refresh', '', origin(source)),
            ]);
            expect(h.kinds, List.filled(6, 'organizationChat'));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite busy disables original direct history and invitation controls but not local directory selection',
      (t) async {
        final h = await mount(t, suite);
        h.change(() => h.view = history(busy: true, notice: '待处理'));
        await frames(t);
        for (final label in [
          '返回会话列表',
          '较早消息',
          '刷新消息',
          '邀请加入组织',
          '查看组织邀请',
          '重新读取',
          '邀请发送记录',
        ]) {
          expect(
            t.widget<StarBridgeActionButton>(button(label)).onActivate,
            isNull,
          );
        }
        h.change(
          () => h.view = const MenuCommsView(
            'ready',
            invitation: MenuFeatureView('ready', scope: 'i1', busy: true),
          ),
        );
        await frames(t);
        expect(
          t.widget<StarBridgeActionButton>(button('返回通讯')).onActivate,
          isNull,
        );
        h.change(() => h.view = fixture(history: false, busy: true));
        await frames(t);
        expect(
          t.widget<StarBridgeActionButton>(button('刷新')).onActivate,
          isNull,
        );
        await fire(
          t,
          'pointer',
          find.byKey(const ValueKey('menu-conversation-c2')),
        );
        await frames(t);
        expect(h.calls, [('select', 'c2', InteractionSource.pointer)]);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite same-context native search preserves composing, selection, focus across live style changes',
      (t) async {
        final h = await mount(t, suite);
        final field = find.byKey(const ValueKey('menu-comms-search'));
        await t.tap(field);
        const value = TextEditingValue(
          text: '北辰abc',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        );
        t.testTextInput.updateEditingValue(value);
        await t.pump();
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final original = t.widget<EditableText>(editable),
            fieldState = t.state(field);
        expect(
          original.controller.value,
          value,
          reason:
              'Verify the native editing precondition before the style update',
        );
        h.change(() {
          h.light = true;
          h.reduce = true;
          h.suite = InteractionSuite.glow;
        });
        await frames(t);
        expect(t.state(field), same(fieldState));
        expect(
          t.widget<EditableText>(editable).controller,
          same(original.controller),
        );
        expect(t.widget<EditableText>(editable).controller.value, value);
        expect(t.widget<EditableText>(editable).focusNode.hasFocus, true);
        expect(h.calls, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite active rapid filter clicks keep every request and selection semantics',
      (t) async {
        final h = await mount(t, suite);
        for (final label in ['未读', '全部', '消息请求', '未读', '全部', '消息请求']) {
          await t.tap(button(label));
          await t.pump(const Duration(milliseconds: 40));
        }
        await frames(t);
        expect(
          find.byKey(const ValueKey('menu-conversation-c3')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('menu-conversation-c2')),
          findsNothing,
        );
        final semantics = t.ensureSemantics();
        try {
          await t.pump();
          final target = find.byKey(
            const ValueKey('menu-comms-group-requests'),
          );
          expect(
            t
                .getSemantics(target)
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            ui.Tristate.isTrue,
          );
          expect(h.calls, isEmpty);
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets(
      '$suite optional narrow organization back preserves callback order and does not become a leave command',
      (t) async {
        final h = await mount(t, suite, viewport: const Size(430, 900));
        h.change(() {
          h.orgSelected = true;
          h.org = organization();
        });
        await frames(t);
        await press(t, 'keyboard', '返回会话列表');
        expect(h.kinds, ['private']);
        expect(h.calls, [('back', '', InteractionSource.keyboard)]);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite selected group native fill reaches actual suite painter',
      (t) async {
        final h = await mount(t, suite);
        await press(t, 'pointer', '未读');
        final chosen = button('未读');
        final nativeStyle = t
            .widget<StarBridgeActionButton>(chosen)
            .nativeStyle!;
        final expected = Theme.of(t.element(chosen))
            .extension<StarBridgeTokens>()!
            .colors
            .info
            .withValues(alpha: .16);
        expect(nativeStyle.backgroundColor!.resolve({}), expected);
        if (suite != InteractionSuite.standard) {
          final actual = find.descendant(
            of: chosen,
            matching: find.byType(SuitePressable),
          );
          expect(
            InteractionScope.of(t.element(actual)).palette.raised,
            expected,
          );
        }
        expect(h.calls, isEmpty);
      },
    );
    testWidgets(
      '$suite selected group keeps the same focus through keyboard selection',
      (t) async {
        await mount(t, suite);
        final label = find
            .descendant(of: button('未读'), matching: find.byType(Text))
            .first;
        final focus = Focus.of(t.element(label));
        focus.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await frames(t);
        expect(Focus.of(t.element(label)), same(focus));
        expect(focus.hasFocus, true);
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await frames(t);
        expect(focus.hasFocus, true);
      },
    );
    testWidgets(
      '$suite Tab can visit private row and its avatar independently',
      (t) async {
        final h = await mount(t, suite);
        await fire(
          t,
          'keyboard',
          find.byKey(const ValueKey('menu-conversation-c1')),
        );
        await frames(t);
        expect(h.calls, [('select', 'c1', InteractionSource.keyboard)]);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await frames(t);
        expect(find.text('查看个人页面'), findsOneWidget);
        expect(h.calls, hasLength(1));
        expect(t.takeException(), isNull);
      },
    );
  }
}
