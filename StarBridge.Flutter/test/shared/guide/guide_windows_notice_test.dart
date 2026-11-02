import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/shared/guide/guide_checklist.dart';
import 'package:starbridge_flutter/shared/guide/guide_controller.dart';
import 'package:starbridge_flutter/shared/guide/guide_page_tip.dart';
import 'package:starbridge_flutter/shared/guide/guide_scope.dart';
import 'package:starbridge_flutter/shared/guide/guide_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_state_adapters.dart';
import 'package:starbridge_flutter/shared/guide/guide_windows_notice.dart';

// N1–N5 of the notifications guide: the Windows notifications card on the
// notifications page and the home checklist item share one "chose" record.

final class _Notice implements GuideWindowsNoticePort {
  _Notice(GuideWindowsNoticeState initial) : state = ValueNotifier(initial);
  @override
  final ValueNotifier<GuideWindowsNoticeState> state;
  bool succeed = true;
  int enables = 0;

  @override
  Future<bool> enable() async {
    enables++;
    if (succeed) state.value = GuideWindowsNoticeState.on;
    return succeed;
  }

  @override
  Widget testButton() => const Text('测试', key: Key('notice-test'));
}

final class _Rig {
  _Rig(GuideState initial, GuideWindowsNoticeState notice)
    : port = InMemoryGuideState(initial),
      notice = _Notice(notice) {
    controller = GuideController(port);
    hub = GuideHub(
      controller: controller,
      online: online,
      navigate: routes.add,
      windowsNotice: this.notice,
    );
  }
  final InMemoryGuideState port;
  final _Notice notice;
  final online = ValueNotifier(true);
  late final GuideController controller;
  late final GuideHub hub;
  final routes = <String>[];
  void dispose() {
    hub.dispose();
    controller.dispose();
    online.dispose();
    notice.state.dispose();
  }
}

const _newUser = GuideState(available: true, eligible: true);

Future<_Rig> _pump(
  WidgetTester tester,
  Widget Function(BuildContext) page, {
  GuideState state = _newUser,
  GuideWindowsNoticeState notice = GuideWindowsNoticeState.off,
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rig = _Rig(state, notice);
  addTearDown(rig.dispose);
  await tester.pumpWidget(_app(rig, page, locale));
  await tester.pumpAndSettle();
  return rig;
}

Widget _app(
  _Rig rig,
  Widget Function(BuildContext) page, [
  Locale locale = const Locale('zh', 'CN'),
]) => MaterialApp(
  key: ObjectKey(page),
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  locale: locale,
  supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  builder: (_, child) => GuideScope(hub: rig.hub, child: child!),
  home: Scaffold(body: Builder(builder: page)),
);

Widget _notifications(BuildContext _) => const GuidePageSurface(
  route: '/notifications',
  available: true,
  child: Text('通知列表'),
);

Widget _home(BuildContext context) => Column(
  children: [guideChecklist(context, fallback: const Text('fallback'))],
);

final _off = find.byKey(const Key('guide-notice-off'));
final _on = find.byKey(const Key('guide-notice-on'));
final _tip = find.byKey(const Key('guide-tip-notifications'));
final _item = find.byKey(const Key('guide-checklist-notify'));

void main() {
  testWidgets('N1/N2: the tip carries the card; turning on asks nothing more', (
    tester,
  ) async {
    final rig = await _pump(tester, _notifications);
    expect(_tip, findsOneWidget);
    expect(_off, findsOneWidget);
    expect(find.text('推荐开启'), findsOneWidget);
    expect(find.text('默认是关的，开不开你说了算。'), findsOneWidget);
    // Off by default: showing the card changes nothing.
    expect(rig.notice.enables, 0);
    expect(rig.controller.value.done, isNot(contains('notify')));

    await tester.tap(find.byKey(const Key('guide-notice-enable')));
    await tester.pumpAndSettle();
    expect(rig.notice.enables, 1);
    expect(rig.controller.value.done, contains('notify'));
    expect(_on, findsOneWidget);
    expect(find.byKey(const Key('notice-test')), findsOneWidget);

    // Leaving the page retires the "on" card; it never comes back.
    rig.hub.visit('/notifications');
    rig.hub.visit('/home');
    await tester.pumpAndSettle();
    expect(_on, findsNothing);
    expect(_off, findsNothing);
    expect(_tip, findsOneWidget, reason: 'the tip itself is unchanged');
  });

  testWidgets('"Later" records the choice and changes no setting', (
    tester,
  ) async {
    final rig = await _pump(tester, _notifications);
    await tester.tap(find.byKey(const Key('guide-notice-later')));
    await tester.pumpAndSettle();
    expect(rig.notice.enables, 0);
    expect(rig.notice.state.value, GuideWindowsNoticeState.off);
    expect(rig.controller.value.done, contains('notify'));
    expect(_off, findsNothing);
    expect(_tip, findsOneWidget);
  });

  testWidgets('a failed save says so and keeps asking', (tester) async {
    final rig = await _pump(tester, _notifications);
    rig.notice.succeed = false;
    await tester.tap(find.byKey(const Key('guide-notice-enable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-notice-failed')), findsOneWidget);
    expect(rig.controller.value.done, isNot(contains('notify')));
    expect(_off, findsOneWidget);
  });

  for (final state in [
    GuideWindowsNoticeState.on,
    GuideWindowsNoticeState.unavailable,
    GuideWindowsNoticeState.loading,
  ]) {
    testWidgets('no card when Windows notifications are ${state.name}', (
      tester,
    ) async {
      await _pump(tester, _notifications, notice: state);
      expect(_tip, findsOneWidget);
      expect(_off, findsNothing);
    });
  }

  testWidgets('old users see the card in the tip too', (tester) async {
    await _pump(
      tester,
      _notifications,
      state: const GuideState(available: true),
    );
    expect(_off, findsOneWidget);
  });

  testWidgets('N5: the item sends the user to the card, even after the tip', (
    tester,
  ) async {
    final rig = await _pump(tester, _home);
    expect(_item, findsOneWidget);
    expect(find.text('打开 Windows 通知'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-checklist-notify-go')));
    await tester.pump();
    expect(rig.routes, ['/notifications']);
    expect(rig.hub.windowsNoticeRequested.value, isTrue);
    // Navigating changes no setting.
    expect(rig.notice.enables, 0);

    // The tip was closed earlier; the card still shows on its own.
    rig.controller.markSeen('tip.notifications');
    await tester.pumpWidget(_app(rig, _notifications));
    await tester.pumpAndSettle();
    expect(_tip, findsNothing);
    expect(_off, findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-notice-later')));
    await tester.pumpAndSettle();
    expect(_off, findsNothing);
    expect(rig.hub.windowsNoticeRequested.value, isFalse);
    expect(rig.controller.value.done, contains('notify'));
  });

  testWidgets('without a request, a closed tip shows no card', (tester) async {
    await _pump(
      tester,
      _notifications,
      state: const GuideState(
        available: true,
        eligible: true,
        seen: {'tip.notifications'},
      ),
    );
    expect(_off, findsNothing);
  });

  testWidgets('a choice on the notifications page completes N5', (
    tester,
  ) async {
    await _pump(
      tester,
      _home,
      state: const GuideState(
        available: true,
        eligible: true,
        done: {'notify'},
      ),
    );
    expect(_item, findsOneWidget);
    expect(find.byKey(const Key('guide-checklist-notify-go')), findsNothing);
  });

  testWidgets('a choice from N5 means no card on the notifications page', (
    tester,
  ) async {
    await _pump(
      tester,
      _notifications,
      state: const GuideState(
        available: true,
        eligible: true,
        done: {'notify'},
      ),
    );
    expect(_tip, findsOneWidget);
    expect(_off, findsNothing);
  });

  testWidgets('already on (e.g. in Settings) counts as done', (tester) async {
    final rig = await _pump(
      tester,
      _home,
      notice: GuideWindowsNoticeState.on,
    );
    expect(find.byKey(const Key('guide-checklist-notify-go')), findsNothing);
    expect(rig.controller.value.done, isNot(contains('notify')));
  });

  testWidgets('no item where Windows notifications are unavailable', (
    tester,
  ) async {
    await _pump(tester, _home, notice: GuideWindowsNoticeState.unavailable);
    expect(find.byKey(const Key('guide-checklist')), findsOneWidget);
    expect(_item, findsNothing);
  });

  testWidgets('the list does not finish while the switch is loading', (
    tester,
  ) async {
    const everything = {
      'recognize',
      'hangar',
      'fleet',
      'overlay',
      'market',
      'friend',
    };
    final rig = await _pump(
      tester,
      _home,
      state: const GuideState(available: true, eligible: true, done: everything),
      notice: GuideWindowsNoticeState.loading,
    );
    expect(find.byKey(const Key('guide-checklist-done')), findsNothing);
    expect(rig.controller.value.celebrated, isFalse);
    rig.notice.state.value = GuideWindowsNoticeState.off;
    await tester.pumpAndSettle();
    expect(_item, findsOneWidget);
    expect(find.byKey(const Key('guide-checklist-done')), findsNothing);
  });

  testWidgets('a finished list stays finished after the new item', (
    tester,
  ) async {
    await _pump(
      tester,
      _home,
      state: const GuideState(available: true, eligible: true, celebrated: true),
    );
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('English card copy', (tester) async {
    await _pump(tester, _notifications, locale: const Locale('en', 'US'));
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Turn on Windows notifications'), findsOneWidget);
  });
}
