import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_flutter/shared/guide/guide_checklist.dart';
import 'package:starbridge_flutter/shared/guide/guide_controller.dart';
import 'package:starbridge_flutter/shared/guide/guide_empty_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_page_tip.dart';
import 'package:starbridge_flutter/shared/guide/guide_scope.dart';
import 'package:starbridge_flutter/shared/guide/guide_settings_section.dart';
import 'package:starbridge_flutter/shared/guide/guide_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_state_adapters.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';

import '../../features/marketplace/marketplace_trades_test.dart'
    show TradesPort;

final class _Rig {
  _Rig(GuideState initial, {bool online = true, bool local = false})
    : port = InMemoryGuideState(initial),
      online = ValueNotifier(online),
      local = ValueNotifier(local) {
    controller = GuideController(port);
    hub = GuideHub(
      controller: controller,
      online: this.online,
      localMode: this.local,
      navigate: routes.add,
    );
  }
  final InMemoryGuideState port;
  final ValueNotifier<bool> online, local;
  late final GuideController controller;
  late final GuideHub hub;
  final routes = <String>[];
  void dispose() {
    hub.dispose();
    controller.dispose();
    online.dispose();
    local.dispose();
  }
}

const _newUser = GuideState(available: true, eligible: true);
const _oldUser = GuideState(available: true);

Future<_Rig> _pump(
  WidgetTester tester,
  Widget page, {
  GuideState state = _newUser,
  bool online = true,
  bool local = false,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rig = _Rig(state, online: online, local: local);
  addTearDown(rig.dispose);
  const locale = Locale('zh', 'CN');
  await tester.pumpWidget(
    MaterialApp(
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
      builder: (_, child) => RepaintBoundary(
        key: const Key('capture'),
        child: GuideScope(hub: rig.hub, child: child!),
      ),
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
  return rig;
}

/// A stand-in market page with the anchors the market tour points at.
Widget _market({VoidCallback? onPublish}) => GuidePageSurface(
  route: '/marketplace',
  available: true,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const GuideAnchor(
        id: 'market.search',
        child: SizedBox(width: 400, height: 36, child: TextField()),
      ),
      Row(
        children: [
          const GuideAnchor(id: 'market.trades', child: Text('交易')),
          const Spacer(),
          GuideAnchor(
            id: 'market.publish',
            child: TextButton(
              key: const Key('publish'),
              onPressed: onPublish,
              child: const Text('发布挂单'),
            ),
          ),
        ],
      ),
      const Expanded(
        child: GuideAnchor(
          id: 'market.offers',
          child: ColoredBox(color: Colors.black12, child: SizedBox.expand()),
        ),
      ),
    ],
  ),
);

class _Probe extends StatefulWidget {
  const _Probe();
  static int inits = 0;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.inits++;
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: SizedBox(width: 300, child: TextField()));
}

void main() {
  setUp(() => _Probe.inits = 0);
  setUpAll(() async {
    for (final font in <String, String>{
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  // 我的交易: a new user with no trades sees the guide's empty state; with only
  // finished trades the active list shows the trades page's own empty state.
  for (final finished in [false, true]) {
    testWidgets('trades empty state: guide only when there are no trades '
        '(finished=$finished)', (tester) async {
      final port = TradesPort();
      if (finished) {
        port.row = {...port.row, 'deliveryStatus': 3, 'transactionStatus': 3};
      } else {
        port.pages[1] = [];
      }
      final market = MarketplaceController(port);
      addTearDown(market.dispose);
      await market.trades.refresh();
      await _pump(tester, MarketplaceTradesPage(market));
      expect(
        find.byType(GuideEmptyState),
        finished ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const Key('market-trades-empty')),
        finished ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a page tip shows once and "知道了" retires it', (tester) async {
    final rig = await _pump(
      tester,
      const GuidePageSurface(
        route: '/rooms',
        available: true,
        child: SizedBox.expand(),
      ),
    );
    expect(find.byKey(const Key('guide-tip-rooms')), findsOneWidget);
    expect(find.text('临时组队与即时状态。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-tip-rooms-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-tip-rooms')), findsNothing);
    expect(rig.port.writes, 1);
    expect((await rig.port.read()).seen, contains('tip.rooms'));
  });

  testWidgets('coming-soon pages and unavailable Host show no tip', (
    tester,
  ) async {
    await _pump(
      tester,
      const GuidePageSurface(
        route: '/operations',
        available: false,
        child: SizedBox.expand(),
      ),
    );
    expect(find.byType(GuideTipStrip), findsNothing);
    await _pump(
      tester,
      const GuidePageSurface(
        route: '/rooms',
        available: true,
        child: SizedBox.expand(),
      ),
      state: GuideState.unavailable,
    );
    expect(find.byType(GuideTipStrip), findsNothing);
  });

  testWidgets(
    'new users get the market tour automatically instead of the tip',
    (tester) async {
      final rig = await _pump(tester, _market());
      expect(find.byKey(const Key('guide-tour-card')), findsOneWidget);
      expect(find.byType(GuideTipStrip), findsNothing);
      expect(find.text('先搜你想要的东西'), findsOneWidget);
      if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
        await expectLater(
          find.byKey(const Key('capture')),
          matchesGoldenFile('goldens/tour-market-step1.png'),
        );
      }
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('guide-tour-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('交易由 SCM 托管'), findsOneWidget);
      expect(find.text('开始使用'), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-tour-back')));
      await tester.pumpAndSettle();
      expect(find.text('交易都在这里跟进'), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-tour-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide-tour-card')), findsNothing);
      final saved = await rig.port.read();
      expect(saved.seen, containsAll(['tour.market', 'tip.market']));
      expect(
        find.byType(GuideTipStrip),
        findsNothing,
        reason: 'tour retired the tip',
      );
    },
  );

  testWidgets('a non-waiting step blocks the page under the scrim', (
    tester,
  ) async {
    var published = 0;
    await _pump(tester, _market(onPublish: () => published++));
    await tester.tap(find.byKey(const Key('publish')), warnIfMissed: false);
    await tester.pump();
    expect(published, 0, reason: 'the tour never acts through the page');
  });

  testWidgets('old users start tours only from "带我走一遍"', (tester) async {
    final rig = await _pump(tester, _market(), state: _oldUser);
    expect(find.byKey(const Key('guide-tour-card')), findsNothing);
    expect(find.byKey(const Key('guide-tip-market')), findsOneWidget);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/tip-market-old-user.png'),
      );
    }
    await tester.tap(find.byKey(const Key('guide-tip-market-tour')));
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.spec.id, 'market');
    expect(find.text('先搜你想要的东西'), findsOneWidget);
  });

  testWidgets('closing or resetting a tip never rebuilds the page', (
    tester,
  ) async {
    final rig = await _pump(
      tester,
      const GuidePageSurface(route: '/rooms', available: true, child: _Probe()),
    );
    await tester.enterText(find.byType(TextField), '草稿');
    expect(_Probe.inits, 1);
    await tester.tap(find.byKey(const Key('guide-tip-rooms-dismiss')));
    await tester.pumpAndSettle();
    rig.controller.resetSeen();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-tip-rooms')), findsOneWidget);
    expect(_Probe.inits, 1, reason: 'same State, no re-initialization');
    expect(find.text('草稿'), findsOneWidget, reason: 'unsaved input kept');
  });

  testWidgets('do-it tours start from the success event, not from clicks', (
    tester,
  ) async {
    final rig = await _pump(
      tester,
      const GuideAnchor(
        id: 'rooms.create',
        child: TextButton(onPressed: null, child: Text('创建房间')),
      ),
    );
    await tester.tap(find.text('创建房间'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      rig.hub.run.value,
      isNull,
      reason: 'a click on a disabled button does nothing',
    );
    rig.hub.report('rooms.formOpened');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.index, 1, reason: 'the event already did step 1');
    rig.hub.report('hangar.saved');
    await tester.pumpAndSettle();
    expect(
      rig.hub.run.value?.index,
      1,
      reason: 'other tours\' events are ignored',
    );
    rig.hub.report('rooms.created');
    await tester.pumpAndSettle();
    expect(
      rig.hub.run.value?.index,
      5,
      reason: 'an early success jumps past the step it completes',
    );
  });

  testWidgets('a waiting step without its anchor offers no "Next"', (
    tester,
  ) async {
    final rig = await _pump(tester, const SizedBox());
    rig.hub.start('hangar', at: 3);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-tour-waiting')), findsOneWidget);
    expect(find.byKey(const Key('guide-tour-next')), findsNothing);
  });

  testWidgets('leaving the flow or the page ends a do-it tour unseen', (
    tester,
  ) async {
    final rig = await _pump(tester, const SizedBox());
    rig.hub.visit('/hangar');
    await tester.pumpAndSettle();
    rig.hub.report('hangar.readerOpened');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.index, 1);
    rig.hub.flowClosed('hangar.reader'); // back out of the reader
    await tester.pumpAndSettle();
    expect(rig.hub.run.value, isNull);
    rig.hub.report('hangar.readerOpened');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.index, 1, reason: 'not recorded as seen');
    rig.hub.visit('/fleet'); // switch pages mid-tour
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.spec.id, isNot('hangar'));
    expect((await rig.port.read()).seen, isNot(contains('tour.hangar')));
  });

  testWidgets('a queued do-it start dies when its flow closes first', (
    tester,
  ) async {
    final rig = await _pump(tester, const SizedBox());
    rig.hub.visit('/hangar');
    await tester.pumpAndSettle();
    rig.hub.report('hangar.readerOpened'); // start queued for the next frame
    rig.hub.flowClosed('hangar.reader'); // reader left before it ran
    await tester.pumpAndSettle();
    expect(rig.hub.run.value, isNull);
    expect((await rig.port.read()).seen, isNot(contains('tour.hangar')));
    rig.hub.report('rooms.formOpened');
    rig.hub.flowClosed('rooms.form');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value, isNull);
  });
  testWidgets('leaving the page of a page tour counts it as seen', (
    tester,
  ) async {
    final rig = await _pump(tester, _market());
    expect(rig.hub.run.value?.spec.id, 'market');
    rig.hub.visit('/rooms');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value, isNull);
    expect((await rig.port.read()).seen, contains('tour.market'));
  });

  testWidgets('a seen do-it tour does not restart', (tester) async {
    final rig = await _pump(
      tester,
      const SizedBox(),
      state: const GuideState(
        available: true,
        eligible: true,
        seen: {'tour.hangar'},
      ),
    );
    rig.hub.report('hangar.readerOpened');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value, isNull);
  });

  testWidgets('waiting steps move on only when the page reports success', (
    tester,
  ) async {
    var saves = 0;
    final rig = await _pump(
      tester,
      GuideAnchor(
        id: 'hangar.save',
        child: Column(
          children: [
            const Text('保存面板里的说明文字'),
            TextButton(
              key: const Key('save'),
              onPressed: () => saves++,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    rig.hub.start('hangar', at: 5);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-tour-waiting')), findsOneWidget);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/tour-hangar-save-wait.png'),
      );
    }
    await tester.tap(find.text('保存面板里的说明文字'));
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(saves, 1, reason: 'the highlighted control works');
    expect(
      rig.hub.run.value?.index,
      5,
      reason: 'a click (or a failed save) is not success',
    );
    rig.hub.report('hangar.saved');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value, isNull);
    expect((await rig.port.read()).seen, contains('tour.hangar'));
  });

  testWidgets('create-room tour on the real form: fill, pick tags, create', (
    tester,
  ) async {
    final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
    addTearDown(module.dispose);
    final rig = await _pump(tester, PartyRoomsPage(module: module));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-create-open')));
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.index, 1);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/tour-rooms-form-interactive.png'),
      );
    }
    // Interactive steps: the form stays usable under the guide.
    await tester.enterText(
      find.byKey(const Key('room-create-title')),
      '导览测试房间',
    );
    await tester.tap(find.byKey(const Key('guide-tour-next')));
    await tester.pumpAndSettle();
    final tags = find.byKey(const Key('room-choose-tags'));
    await tester.ensureVisible(tags);
    await tester.tap(tags);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tag-catalog-search')),
      '不知道玩啥',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-tag-undecided')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-tags-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guide-tour-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guide-tour-next')));
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.index, 4);
    await tester.tap(find.widgetWithText(FilledButton, '创建房间').last);
    await tester.pumpAndSettle();
    expect(module.directory!.currentRoomId, 'example-created');
    expect(
      rig.hub.run.value?.index,
      5,
      reason: 'moved on after the room was created',
    );
    expect(tester.takeException(), isNull);
    // Let the room's own feedback timer run out with the page gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('cancelling the real form ends the tour unseen', (tester) async {
    final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
    addTearDown(module.dispose);
    final rig = await _pump(tester, PartyRoomsPage(module: module));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-create-open')));
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.index, 1);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(rig.hub.run.value, isNull, reason: 'no orphaned card');
    expect(find.byKey(const Key('guide-tour-card')), findsNothing);
    expect((await rig.port.read()).seen, isNot(contains('tour.rooms')));
  });

  testWidgets('creating straight away jumps the tour to the last step', (
    tester,
  ) async {
    final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
    addTearDown(module.dispose);
    final rig = await _pump(tester, PartyRoomsPage(module: module));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-create-open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('room-create-title')), '直接创建');
    final tags = find.byKey(const Key('room-choose-tags'));
    await tester.ensureVisible(tags);
    await tester.tap(tags);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tag-catalog-search')),
      '不知道玩啥',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-tag-undecided')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-tags-confirm')));
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.index, 1, reason: 'still on the first form step');
    await tester.tap(find.widgetWithText(FilledButton, '创建房间').last);
    await tester.pumpAndSettle();
    expect(module.directory!.currentRoomId, 'example-created');
    expect(rig.hub.run.value?.index, 5);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a failed create does not move the tour on', (tester) async {
    final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
    addTearDown(module.dispose);
    final rig = await _pump(tester, PartyRoomsPage(module: module));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-create-open')));
    await tester.pumpAndSettle();
    rig.hub.start('rooms', at: 4);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建房间').last);
    await tester.pumpAndSettle();
    expect(find.text('名称需要 2–32 个字符。'), findsOneWidget);
    expect(rig.hub.run.value?.index, 4);
  });

  testWidgets('after "show tips again" the automatic tour comes back', (
    tester,
  ) async {
    final rig = await _pump(tester, _market());
    await tester.tap(find.byKey(const Key('guide-tour-skip')));
    await tester.pumpAndSettle();
    expect(rig.hub.run.value, isNull);
    rig.controller.resetSeen();
    await tester.pumpAndSettle();
    rig.hub.visit('/marketplace');
    await tester.pumpAndSettle();
    expect(rig.hub.run.value?.spec.id, 'market');
  });

  testWidgets('online checklist: progress, navigation, collapse, dismiss', (
    tester,
  ) async {
    final rig = await _pump(
      tester,
      Builder(
        builder: (context) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: guideChecklist(context, fallback: const Text('fallback')),
          ),
        ),
      ),
      state: const GuideState(
        available: true,
        eligible: true,
        done: {'recognize', 'hangar'},
      ),
    );
    expect(find.byKey(const Key('guide-checklist')), findsOneWidget);
    expect(find.text('2 / 6'), findsOneWidget);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/checklist-online.png'),
      );
    }
    await tester.tap(find.byKey(const Key('guide-checklist-fleet-go')));
    expect(rig.routes, ['/fleet']);
    await tester.tap(find.byKey(const Key('guide-checklist-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-checklist-fleet')), findsNothing);
    await tester.tap(find.byKey(const Key('guide-checklist-dismiss')));
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('local checklist lists local items and the online note', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) =>
            guideChecklist(context, fallback: const SizedBox()),
      ),
      online: false,
    );
    expect(find.text('0 / 5'), findsOneWidget);
    expect(find.byKey(const Key('guide-checklist-friend')), findsNothing);
    expect(find.text('游戏里显示什么、摆在哪，按你的习惯设置。'), findsOneWidget);
    expect(find.textContaining('换成在线账号'), findsOneWidget);
  });

  testWidgets('old users never see the checklist', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) =>
            guideChecklist(context, fallback: const Text('fallback')),
      ),
      state: _oldUser,
    );
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('finishing the last item celebrates once', (tester) async {
    final rig = await _pump(
      tester,
      Builder(
        builder: (context) =>
            guideChecklist(context, fallback: const Text('fallback')),
      ),
      state: const GuideState(
        available: true,
        eligible: true,
        done: {'recognize', 'hangar', 'fleet', 'overlay', 'market', 'friend'},
      ),
    );
    expect(find.byKey(const Key('guide-checklist-done')), findsOneWidget);
    expect((await rig.port.read()).celebrated, isTrue);
    await tester.tap(find.byKey(const Key('guide-checklist-close')));
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('the listing demo never posts', (tester) async {
    final rig = await _pump(tester, _market(), state: _oldUser);
    await tester.tap(find.byKey(const Key('guide-tip-market-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-listing-demo')), findsOneWidget);
    expect(find.text('示例 · 不会发布'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('guide-listing-demo-next')));
      await tester.pumpAndSettle();
    }
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/listing-demo-confirm.png'),
      );
    }
    final publish = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('guide-listing-demo-publish')),
    );
    expect(
      publish.onPressed,
      isNull,
      reason: 'publishing is disabled in the sample',
    );
    await tester.tap(find.byKey(const Key('guide-listing-demo-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-listing-demo')), findsNothing);
    expect(
      rig.port.writes,
      0,
      reason: 'the demo writes nothing, not even the tip',
    );
  });

  testWidgets('guided empty and local-mode states', (tester) async {
    var refreshed = 0;
    await _pump(
      tester,
      Builder(
        builder: (context) => Column(
          children: [
            Expanded(
              child: GuideEmptyState(
                'rooms',
                onPrimary: () {},
                onSecondary: () => refreshed++,
              ),
            ),
            Expanded(
              child: guideOnlineRequired(context, '交易大厅') ?? const SizedBox(),
            ),
          ],
        ),
      ),
      local: true,
    );
    expect(find.text('现在没人建房'), findsOneWidget);
    expect(find.text('交易大厅要在线账号才能用'), findsOneWidget);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('capture')),
        matchesGoldenFile('goldens/empty-rooms-and-local.png'),
      );
    }
    await tester.tap(find.byKey(const Key('guide-empty-rooms-secondary')));
    expect(refreshed, 1);
  });

  testWidgets(
    'online accounts that are merely signed out keep their own copy',
    (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) =>
              guideOnlineRequired(context, '交易大厅') ?? const Text('own'),
        ),
      );
      expect(find.text('own'), findsOneWidget);
    },
  );

  testWidgets('settings bring tips and the checklist back', (tester) async {
    final rig = await _pump(
      tester,
      GuideSettingsSection(
        panel: (title, subtitle, child) =>
            Column(children: [Text(title), child]),
      ),
      state: const GuideState(
        available: true,
        eligible: true,
        seen: {'tip.fleet'},
        dismissed: true,
      ),
    );
    await tester.tap(find.byKey(const Key('guide-settings-resetChecklist')));
    await tester.tap(find.byKey(const Key('guide-settings-resetTips')));
    await tester.pumpAndSettle();
    final state = await rig.port.read();
    expect(state.dismissed, isFalse);
    expect(state.seen, isEmpty);
    expect(find.text('已重新打开'), findsOneWidget);
  });
}
