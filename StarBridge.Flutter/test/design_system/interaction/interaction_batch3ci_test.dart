import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_controls.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import '../../app/menu_overlay/menu_friends_usability_test.dart' show roster;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3aa_test.dart' show reader;
import 'interaction_batch3ca_test.dart' show fire;

const avatarKey = Key('avatar-trigger');
const extraKey = Key('extra-action');

class Harness extends StatefulWidget {
  const Harness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  bool reduce = false, light = false, nativeActive = true, visible = true;
  bool profile = true, extra = true;
  String target = 'a', name = '同名用户', avatar = 'A';
  final calls = <(String, InteractionSource)>[];
  MenuController? controller;
  void change(VoidCallback fn) => setState(fn);
  @override
  Widget build(BuildContext context) => scopedApp(
    NativeViewportScope(
      active: nativeActive,
      child: Center(
        child: visible
            ? MenuAvatarActions(
                key: avatarKey,
                identity: target,
                name: name,
                onProfile: profile
                    ? () =>
                          calls.add((target, currentStarBridgeActivationSource))
                    : null,
                actions: [
                  StarBridgeMenuEntry(
                    id: 'extra',
                    controlKey: extraKey,
                    label: '附加操作',
                    child: const Text('附加操作'),
                    onActivate: extra
                        ? (_) => calls.add((
                            'extra:$target',
                            currentStarBridgeActivationSource,
                          ))
                        : null,
                  ),
                ],
                child: SizedBox.square(dimension: 32, child: Text(avatar)),
              )
            : const Text('已离开'),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<HarnessState> mount(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(suite, key: key));
  await frames(t);
  return key.currentState!;
}

Finder row(Object id) => find.byKey(ValueKey<Object>(id));

Future<void> openAvatar(WidgetTester t, String input) async {
  if (input == 'reader') {
    reader(t, '同名用户 · 头像菜单');
    await t.pump();
    await t.pump();
  } else {
    await fire(t, input, find.byKey(avatarKey));
  }
}

Future<void> choose(
  WidgetTester t,
  String input,
  String label,
  Finder target,
) async {
  await t.ensureVisible(target);
  await t.pump();
  if (input == 'reader') {
    reader(t, label);
    await t.pump();
    await t.pump();
  } else if (input == 'keyboard') {
    final widget = t.widget(target);
    if (widget is SuitePressable) widget.focusNode!.requestFocus();
    if (widget is MenuItemButton) widget.focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
  } else {
    await t.tap(target);
    await t.pump();
    await t.pump();
  }
}

MenuFriendsView friends({
  bool busy = false,
  bool refresh = false,
  String scope = 'friends1',
  String ownKey = 'self1',
}) => MenuFriendsView(
  'ready',
  interactive: true,
  identity: roster.identity,
  scope: scope,
  rows: roster.rows,
  actions: roster.actions,
  chatKeys: roster.chatKeys,
  busy: busy,
  requiresRefresh: refresh,
  self: (
    key: ownKey,
    status: 'presence.online',
    change: true,
    busy: false,
    failed: false,
  ),
);

void main() {
  for (final suite in InteractionSuite.values) {
    for (final placement in [
      'short-below',
      'large-above',
      'crowded-scroll',
      'rtl-width',
    ]) {
      testWidgets(
        '$suite no-header $placement keeps actual layout and transition origin aligned',
        (t) async {
          size(t, const Size(430, 1000));
          final count = placement == 'short-below'
              ? 1
              : placement == 'crowded-scroll'
              ? 30
              : 8;
          final calls = <int>[];
          await t.pumpWidget(
            scopedApp(
              MediaQuery(
                data: MediaQueryData(
                  size: const Size(430, 1000),
                  textScaler: TextScaler.linear(
                    placement == 'short-below' ? 1 : 2,
                  ),
                ),
                child: Directionality(
                  textDirection: placement == 'rtl-width'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Stack(
                    children: [
                      Positioned(
                        top: placement == 'crowded-scroll' ? 480 : 700,
                        left: 30,
                        width: 190,
                        child: StarBridgeMenuAnchor(
                          semanticLabel: '布局菜单',
                          matchAnchorWidth: placement == 'rtl-width',
                          maximumSize: const Size(300, 400),
                          entries: [
                            for (var i = 0; i < count; i++)
                              StarBridgeMenuEntry(
                                id: i,
                                label: '操作$i',
                                onActivate: (_) => calls.add(i),
                                child: Text(
                                  '操作$i${placement == 'short-below' ? '' : ' · 这是需要多行显示的菜单内容'}',
                                ),
                              ),
                          ],
                          builder: (_, controller, focus, toggle) => TextButton(
                            key: const Key('placement-trigger'),
                            focusNode: focus,
                            onPressed: () => toggle(InteractionSource.pointer),
                            child: const Text('打开菜单'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              suite,
            ),
          );
          await frames(t);
          final trigger = find.byKey(const Key('placement-trigger'));
          await t.tap(trigger);
          await frames(t);
          final surface = t.widget<SuiteSurfaceTransition>(
            find.byType(SuiteSurfaceTransition),
          );
          final first = t.getRect(row(0)), anchor = t.getRect(trigger);
          expect(first.left, greaterThanOrEqualTo(8));
          expect(first.right, lessThanOrEqualTo(422));
          if (placement == 'short-below') {
            expect(first.top, greaterThan(anchor.bottom));
            expect(surface.alignment.y, -1);
          }
          if (placement == 'large-above') {
            expect(first.top, lessThan(anchor.top));
            expect(surface.alignment.y, 1);
          }
          if (placement == 'rtl-width') {
            expect(first.width, lessThanOrEqualTo(anchor.width));
            expect(first.right, lessThanOrEqualTo(anchor.right));
          }
          final last = row(count - 1);
          await t.ensureVisible(last);
          await t.pump();
          final rect = t.getRect(last);
          expect(rect.top, greaterThanOrEqualTo(8));
          expect(rect.bottom, lessThanOrEqualTo(992));
          await t.tap(last);
          await frames(t);
          expect(calls, [count - 1]);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await frames(t);
        },
      );
    }
    testWidgets('$suite avatar is exactly one Tab stop between neighbours', (
      t,
    ) async {
      final before = FocusNode(), after = FocusNode();
      try {
        await t.pumpWidget(
          scopedApp(
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  focusNode: before,
                  onPressed: () {},
                  child: const Text('前一个'),
                ),
                MenuAvatarActions(
                  key: avatarKey,
                  identity: 'a',
                  name: '同名用户',
                  onProfile: () {},
                  child: const Text('头像'),
                ),
                TextButton(
                  focusNode: after,
                  onPressed: () {},
                  child: const Text('后一个'),
                ),
              ],
            ),
            suite,
          ),
        );
        await frames(t);
        before.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        final trigger = t.widget<BridgeMenuAction>(
          find.descendant(
            of: find.byKey(avatarKey),
            matching: find.byType(BridgeMenuAction),
          ),
        );
        expect(trigger.focusNode!.hasPrimaryFocus, true);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(after.hasPrimaryFocus, true);
      } finally {
        await t.pumpWidget(const SizedBox());
        await frames(t);
        before.dispose();
        after.dispose();
      }
    });
    testWidgets(
      '$suite disabling focused live action repairs focus to latest enabled row',
      (t) async {
        final h = await mount(t, suite);
        await openAvatar(t, 'keyboard');
        await frames(t);
        final extra = t.widget(find.byKey(extraKey));
        if (extra is SuitePressable) extra.focusNode!.requestFocus();
        if (extra is MenuItemButton) extra.focusNode!.requestFocus();
        await t.pump();
        h.change(() => h.extra = false);
        await t.pump();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await frames(t);
        expect(h.calls, [('a', InteractionSource.keyboard)]);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input actual avatar dispatch preserves source once',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await mount(t, suite);
            await openAvatar(t, input);
            await frames(t);
            expect(nativeViewportMenus.value, 1);
            await choose(t, input, '查看个人页面', row('avatar-profile'));
            expect(h.calls, [
              (
                'a',
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            if (input != 'pointer') expect(nativeViewportMenus.value, 0);
            await frames(t);
            expect(nativeViewportMenus.value, 0);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite actual keyboard close returns to a reopenable trigger',
      (t) async {
        await mount(t, suite);
        await openAvatar(t, 'keyboard');
        await frames(t);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(nativeViewportMenus.value, 0);
        final trigger = t.widget<BridgeMenuAction>(
          find.descendant(
            of: find.byKey(avatarKey),
            matching: find.byType(BridgeMenuAction),
          ),
        );
        expect(trigger.focusNode!.hasPrimaryFocus, true);
        // The SDK anchor and the painted trigger are one traversal stop.
        expect(
          find
              .descendant(
                of: find.byKey(avatarKey),
                matching: find.byWidgetPredicate(
                  (w) => w is Focus && w.focusNode == trigger.focusNode,
                ),
              )
              .evaluate(),
          hasLength(1),
        );
        final painted = find.descendant(
          of: find.byKey(avatarKey),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        );
        expect(
          painted.evaluate().any(
            (e) =>
                ((e.widget as Container).decoration! as BoxDecoration)
                    .border
                    ?.bottom
                    .color
                    .a ==
                1,
          ),
          true,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        await t.pump();
        expect(row('avatar-profile'), findsOneWidget);
        expect(nativeViewportMenus.value, 1);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
    for (final retirement in ['target', 'native', 'dispose']) {
      testWidgets(
        '$suite $retirement retires an open avatar without stale action',
        (t) async {
          final h = await mount(t, suite);
          await openAvatar(t, 'pointer');
          await frames(t);
          h.change(() {
            if (retirement == 'target') h.target = 'b';
            if (retirement == 'native') h.nativeActive = false;
            if (retirement == 'dispose') h.visible = false;
          });
          await t.pump();
          await t.pump();
          expect(row('avatar-profile'), findsNothing);
          expect(nativeViewportMenus.value, 0);
          expect(h.calls, isEmpty);
          await frames(t);
          expect(nativeViewportMenus.value, 0);
          if (retirement == 'target') {
            await openAvatar(t, 'pointer');
            await frames(t);
            await choose(t, 'pointer', '查看个人页面', row('avatar-profile'));
            expect(h.calls.single.$1, 'b');
          }
          await t.pumpWidget(const SizedBox());
          await frames(t);
        },
      );
    }
    testWidgets('$suite ordinary media and callback refresh keeps one popup', (
      t,
    ) async {
      final h = await mount(t, suite);
      await openAvatar(t, 'pointer');
      await frames(t);
      h.change(() {
        h.name = '更新的名称';
        h.avatar = 'B';
      });
      await t.pump();
      await t.pump();
      expect(row('avatar-profile'), findsOneWidget);
      expect(find.text('更新的名称'), findsOneWidget);
      expect(nativeViewportMenus.value, 1);
      h.change(() => h.extra = false);
      await t.pump();
      await t.tap(find.byKey(extraKey), warnIfMissed: false);
      expect(h.calls, isEmpty);
      await choose(t, 'pointer', '查看个人页面', row('avatar-profile'));
      expect(h.calls.single.$1, 'a');
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
    testWidgets(
      '$suite open avatar follows live theme/reduce within two frames',
      (t) async {
        final h = await mount(t, suite);
        await openAvatar(t, 'pointer');
        await t.pump(const Duration(milliseconds: 25));
        h.change(() {
          h.reduce = true;
          h.light = true;
        });
        await t.pump();
        await t.pump();
        final surface = find
            .ancestor(
              of: row('avatar-profile'),
              matching: find.byType(Material),
            )
            .first;
        final context = t.element(surface);
        expect(InteractionScope.of(context).animates, false);
        expect(Theme.of(context).brightness, Brightness.light);
        await choose(t, 'pointer', '查看个人页面', row('avatar-profile'));
        expect(nativeViewportMenus.value, 0);
        expect(h.calls, hasLength(1));
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
    for (final gate in ['busy', 'refresh']) {
      testWidgets(
        '$suite friend $gate keeps profile/chat but omits destructive actions',
        (t) async {
          final calls = <String>[];
          await t.pumpWidget(
            scopedApp(
              Center(
                child: SizedBox(
                  width: 340,
                  height: 900,
                  child: MenuFriendsPanel(
                    view: friends(
                      busy: gate == 'busy',
                      refresh: gate == 'refresh',
                    ),
                    onClose: () {},
                    onProfile: (key) => calls.add('profile:$key'),
                    onChat: (key) => calls.add('chat:$key'),
                    onAction: (a, k, v) => calls.add('$a:$k:$v'),
                  ),
                ),
              ),
              suite,
            ),
          );
          await frames(t);
          await t.tap(find.byKey(const ValueKey('f1')));
          await frames(t);
          expect(row('avatar-profile'), findsOneWidget);
          final menu = t
              .widgetList<StarBridgeMenuAnchor>(
                find.byType(StarBridgeMenuAnchor),
              )
              .singleWhere((m) => m.semanticLabel == '北辰 · 头像菜单');
          expect(
            menu.entries.firstWhere((e) => e.id == 'friend-chat-f1').onActivate,
            isNotNull,
          );
          expect(menu.entries.any((e) => e.id == 'friend-remove-f1'), false);
          expect(find.byKey(const ValueKey('friend-remove-f1')), findsNothing);
          expect(calls, isEmpty);
          await t.tap(find.byKey(const ValueKey('friend-chat-f1')));
          await frames(t);
          expect(calls, ['chat:f1']);
          await t.pumpWidget(const SizedBox());
          await frames(t);
        },
      );
    }
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input presence/manage preserve original payload and busy gate',
        (t) async {
          final semantics = t.ensureSemantics(),
              view = ValueNotifier(friends());
          final calls = <(String, String, String, InteractionSource)>[];
          try {
            await t.pumpWidget(
              scopedApp(
                Center(
                  child: SizedBox(
                    width: 340,
                    child: ValueListenableBuilder<MenuFriendsView>(
                      valueListenable: view,
                      builder: (_, v, _) => MenuFriendsControls(
                        view: v,
                        onAction: (a, k, v) => calls.add((
                          a,
                          k,
                          v,
                          currentStarBridgeActivationSource,
                        )),
                      ),
                    ),
                  ),
                ),
                suite,
              ),
            );
            await frames(t);
            Future<void> openLabel(String label) async {
              if (input == 'reader') {
                reader(t, label);
                await t.pump();
                await t.pump();
              } else {
                final menu = find.byWidgetPredicate(
                  (w) => w is StarBridgeMenuAnchor && w.semanticLabel == label,
                );
                final trigger = find.descendant(
                  of: menu,
                  matching: find.byWidgetPredicate(
                    (w) => w.runtimeType.toString() == 'BridgeMenuAction',
                  ),
                );
                await fire(t, input, trigger);
              }
            }

            await openLabel('更改我的在线状态');
            await frames(t);
            await choose(t, input, '隐身', row('friends-presence-invisible'));
            await frames(t);
            expect(calls.single, (
              'presence',
              'self1',
              'invisible',
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ));
            view.value = friends(busy: true);
            await frames(t);
            await openLabel('好友管理');
            await frames(t);
            expect(
              find.byKey(const ValueKey('friends-section-incoming')),
              findsOneWidget,
            );
            final menu = t
                .widgetList<StarBridgeMenuAnchor>(
                  find.byType(StarBridgeMenuAnchor),
                )
                .singleWhere((m) => m.semanticLabel == '好友管理');
            expect(menu.enabled, true);
            expect(menu.entries.every((e) => e.onActivate == null), true);
            view.value = friends();
            await frames(t);
            await choose(
              t,
              input,
              '收到的申请',
              find.byKey(const ValueKey('friends-section-incoming')),
            );
            await frames(t);
            expect(calls.last.$1, 'section');
            expect(calls.last.$3, 'incoming');
            expect(calls, hasLength(2));
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            view.dispose();
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite presence identity follows own opaque key not only friends scope',
      (t) async {
        final view = ValueNotifier(friends());
        await t.pumpWidget(
          scopedApp(
            Center(
              child: SizedBox(
                width: 340,
                child: ValueListenableBuilder<MenuFriendsView>(
                  valueListenable: view,
                  builder: (_, v, _) =>
                      MenuFriendsControls(view: v, onAction: (_, _, _) {}),
                ),
              ),
            ),
            suite,
          ),
        );
        await frames(t);
        final semantics = t.ensureSemantics();
        reader(t, '更改我的在线状态');
        await frames(t);
        expect(nativeViewportMenus.value, 1);
        view.value = friends(ownKey: 'self2');
        await t.pump();
        await t.pump();
        expect(row('friends-presence-invisible'), findsNothing);
        expect(nativeViewportMenus.value, 0);
        await t.pumpWidget(const SizedBox());
        await frames(t);
        view.dispose();
        semantics.dispose();
      },
    );
    testWidgets('$suite actual friend avatar preserves all original actions', (
      t,
    ) async {
      size(t, const Size(900, 1000));
      await t.pumpWidget(
        scopedApp(
          Center(
            child: SizedBox(
              width: 340,
              height: 900,
              child: MenuFriendsPanel(
                view: roster,
                onClose: () {},
                onProfile: (_) {},
                onChat: (_) {},
                onAction: (_, _, _) {},
              ),
            ),
          ),
          suite,
        ),
      );
      await frames(t);
      final menus = t.widgetList<StarBridgeMenuAnchor>(
        find.byType(StarBridgeMenuAnchor),
      );
      final avatar = menus.singleWhere((m) => m.semanticLabel == '北辰 · 头像菜单');
      expect(avatar.entries.map((e) => e.id), contains('friend-remove-f1'));
      await t.tap(find.byKey(const ValueKey('f1')));
      await frames(t);
      expect(nativeViewportMenus.value, 1);
      expect(find.byKey(const ValueKey('friend-remove-f1')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
  }
}
