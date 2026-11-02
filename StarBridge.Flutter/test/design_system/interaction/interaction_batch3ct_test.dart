import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_notice_banner.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_surface_app_frame.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';
import 'package:starbridge_flutter/platform/window/menu_notice.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;

const closeKey = Key('menu-notice-close');
const notice = MenuNotice('新的消息', '这条消息仅供本地显示。');

Widget host(Widget child, InteractionSuite suite, {bool reduce = false}) =>
    MenuSurfaceAppFrame(
      observer: NavigatorObserver(),
      interaction: MenuInteractionPresentation(
        style: MenuInteractionStyle.values.byName(suite.name),
        reduceMotion: reduce,
      ),
      child: Scaffold(body: Center(child: child)),
    );

Future<void> detach(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void main() {
  setUpAll(loadFonts);

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite live auxiliary style/reduce keeps focus and the original deadline',
      (t) async {
        late StateSetter update;
        var currentSuite = suite;
        var reduce = false;
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  const SizedBox(
                    width: 360,
                    child: MenuNoticeBanner(notice: notice),
                  ),
                  currentSuite,
                  reduce: reduce,
                );
              },
            ),
          );
          await t.pump();
          final focus = t.widget<IconButton>(find.byKey(closeKey)).focusNode;
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
          await t.pump();
          await t.pump(const Duration(milliseconds: 800));
          expect(find.text('关闭'), findsOneWidget);
          update(() {
            currentSuite = InteractionSuite
                .values[(suite.index + 1) % InteractionSuite.values.length];
            reduce = true;
          });
          await t.pump();
          await t.pump();
          final effective = InteractionScope.of(
            t.element(find.byType(SuiteTooltip)),
          );
          expect(effective.suite, currentSuite);
          expect(effective.reduceMotion, isTrue);
          expect(
            t.widget<IconButton>(find.byKey(closeKey)).focusNode,
            same(focus),
          );
          final bubbleOpacity = find
              .ancestor(of: find.text('关闭'), matching: find.byType(Opacity))
              .first;
          expect(t.widget<Opacity>(bubbleOpacity).opacity, 1);
          await t.pump(const Duration(seconds: 3));
          expect(find.text(notice.title), findsOneWidget);
          await t.pump(const Duration(milliseconds: 300));
          expect(find.text(notice.title), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await detach(t);
        }
      },
    );

    testWidgets(
      '$suite passive replacements show only latest and never queue',
      (t) async {
        late StateSetter update;
        var current = notice;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  SizedBox(
                    width: 360,
                    child: MenuNoticeBanner(notice: current),
                  ),
                  suite,
                );
              },
            ),
          );
          await t.pump();
          for (var i = 0; i < 12; i++) {
            update(() => current = MenuNotice('本地消息$i', '只有最新一项。'));
            await t.pump(const Duration(milliseconds: 50));
            expect(find.text('本地消息$i'), findsOneWidget);
            if (i > 0) expect(find.text('本地消息${i - 1}'), findsNothing);
          }
          await t.pump(const Duration(milliseconds: 3999));
          expect(find.text('本地消息11'), findsOneWidget);
          await t.pump(const Duration(milliseconds: 1));
          expect(find.text('本地消息11'), findsNothing);
          await t.pump(const Duration(seconds: 5));
          expect(find.byKey(closeKey), findsNothing);
        } finally {
          await detach(t);
        }
      },
    );

    testWidgets('$suite disposal retires both expiry and a waiting hint', (
      t,
    ) async {
      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await t.pumpWidget(
          host(
            const SizedBox(width: 360, child: MenuNoticeBanner(notice: notice)),
            suite,
          ),
        );
        await t.pump();
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
        await t.pump(const Duration(milliseconds: 200));
        await detach(t);
        await t.pump(const Duration(seconds: 5));
        expect(find.text('关闭'), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await detach(t);
      }
    });

    testWidgets('$suite actual notice close hint follows auxiliary frame', (
      t,
    ) async {
      await t.pumpWidget(
        host(
          const SizedBox(
            width: 360,
            child: MenuNoticeBanner(notice: MenuNotice('新的消息', '这条消息仅供本地显示。')),
          ),
          suite,
        ),
      );
      await t.pump();
      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(find.byType(IconButton)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('关闭'), findsOneWidget);
      expect(find.byType(SuiteTooltip), findsOneWidget);
      final tooltipContext = t.element(find.byType(SuiteTooltip));
      expect(InteractionScope.of(tooltipContext).suite, suite);
      await mouse.removePointer();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    });

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source local close clears immediately and stays dismissed',
        (t) async {
          final semantics = t.ensureSemantics();
          late StateSetter update;
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return host(
                    const SizedBox(
                      width: 360,
                      child: MenuNoticeBanner(notice: notice),
                    ),
                    suite,
                  );
                },
              ),
            );
            await t.pump();
            final named = find.bySemanticsLabel('关闭');
            expect(named, findsOneWidget);
            final node = t.getSemantics(named);
            expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
            if (source == 'pointer') {
              await t.tap(find.byKey(closeKey));
            } else if (source == 'keyboard') {
              t
                  .widget<IconButton>(find.byKey(closeKey))
                  .focusNode!
                  .requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              t.binding.performSemanticsAction(
                ui.SemanticsActionEvent(
                  type: ui.SemanticsAction.tap,
                  viewId: t.view.viewId,
                  nodeId: node.id,
                ),
              );
            }
            await t.pump();
            expect(find.text(notice.title), findsNothing);
            update(() {});
            await t.pump();
            expect(find.text(notice.title), findsNothing);
            await t.pump(const Duration(seconds: 5));
            expect(find.text(notice.title), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await detach(t);
          }
        },
      );
    }

    testWidgets('$suite expiry remains exactly four seconds', (t) async {
      try {
        await t.pumpWidget(
          host(
            const SizedBox(width: 360, child: MenuNoticeBanner(notice: notice)),
            suite,
          ),
        );
        await t.pump();
        expect(find.text(notice.title), findsOneWidget);
        await t.pump(const Duration(milliseconds: 3999));
        expect(find.text(notice.title), findsOneWidget);
        await t.pump(const Duration(milliseconds: 1));
        expect(find.text(notice.title), findsNothing);
      } finally {
        await detach(t);
      }
    });

    testWidgets('$suite same instance rebuild does not reset expiry', (
      t,
    ) async {
      late StateSetter update;
      try {
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return host(
                const SizedBox(
                  width: 360,
                  child: MenuNoticeBanner(notice: notice),
                ),
                suite,
              );
            },
          ),
        );
        await t.pump();
        expect(find.text(notice.title), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
        update(() {});
        await t.pump();
        await t.pump(const Duration(milliseconds: 2999));
        expect(find.text(notice.title), findsOneWidget);
        await t.pump(const Duration(milliseconds: 1));
        expect(find.text(notice.title), findsNothing);
      } finally {
        await detach(t);
      }
    });

    testWidgets(
      '$suite replacement cancels old expiry and owns the latest four seconds',
      (t) async {
        late StateSetter update;
        var current = notice;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  SizedBox(
                    width: 360,
                    child: MenuNoticeBanner(notice: current),
                  ),
                  suite,
                );
              },
            ),
          );
          await t.pump();
          expect(find.text(notice.title), findsOneWidget);
          await t.pump(const Duration(seconds: 3));
          update(() => current = const MenuNotice('最新消息', '最新的本地提示。'));
          await t.pump();
          expect(find.text(notice.title), findsNothing);
          await t.pump(const Duration(seconds: 1));
          expect(find.text('最新消息'), findsOneWidget);
          await t.pump(const Duration(milliseconds: 2999));
          expect(find.text('最新消息'), findsOneWidget);
          await t.pump(const Duration(milliseconds: 1));
          expect(find.text('最新消息'), findsNothing);
        } finally {
          await detach(t);
        }
      },
    );

    testWidgets(
      '$suite new identity revives local dismissal without acknowledging the source',
      (t) async {
        late StateSetter update;
        var current = notice;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  SizedBox(
                    width: 360,
                    child: MenuNoticeBanner(notice: current),
                  ),
                  suite,
                );
              },
            ),
          );
          await t.pump();
          expect(find.text(notice.title), findsOneWidget);
          await t.tap(find.byKey(closeKey));
          await t.pump();
          expect(find.text(notice.title), findsNothing);
          expect(identical(current, notice), isTrue);
          update(() => current = MenuNotice(notice.title, notice.message));
          await t.pump();
          expect(find.text(notice.title), findsOneWidget);
          expect(current.toMap(), {
            'title': notice.title,
            'message': notice.message,
          });
        } finally {
          await detach(t);
        }
      },
    );

    testWidgets(
      '$suite actual bridge close does not dismiss the menu or clear its input notice',
      (t) async {
        var dismissals = 0;
        try {
          await t.pumpWidget(
            host(
              MenuBridgePreview(
                visible: true,
                onDismiss: () => dismissals++,
                notice: notice,
              ),
              suite,
            ),
          );
          await t.pump();
          await t.tap(find.byKey(closeKey));
          await t.pump();
          expect(find.text(notice.title), findsNothing);
          expect(find.byType(MenuBridgePreview), findsOneWidget);
          expect(
            t.widget<MenuBridgePreview>(find.byType(MenuBridgePreview)).notice,
            same(notice),
          );
          expect(dismissals, 0);
          expect(t.takeException(), isNull);
        } finally {
          await detach(t);
        }
      },
    );
  }
}
