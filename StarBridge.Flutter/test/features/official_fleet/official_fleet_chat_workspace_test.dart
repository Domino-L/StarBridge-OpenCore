import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_chat_workspace.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';

class _RecordingPort implements OfficialFleetMembersPort {
  _RecordingPort(this.inner);
  final OfficialFleetMembersPort inner;
  final queries = <OfficialFleetMemberDirectoryQuery>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) {
    queries.add(query);
    return inner.read(query);
  }

  @override
  Future<void> close() async {}
}

Future<void> _pump(WidgetTester tester, Widget child, {double width = 1200}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('online column groups the page\'s members without its own read', (
    tester,
  ) async {
    final port = _RecordingPort(
      InMemoryOfficialFleetMembersAdapter.forReview(),
    );
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    await module.open('officialFleet:7');
    final reads = port.queries.length;
    await _pump(tester, OfficialFleetOnlinePane(members: module.projection));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(port.queries, hasLength(reads), reason: 'No second read.');
    final online = module.projection.value.members.where(
      (m) => const {
        OfficialFleetMemberPresence.online,
        OfficialFleetMemberPresence.inGame,
      }.contains(m.publicPresence),
    );
    final inGame = online
        .where((m) => m.publicPresence == OfficialFleetMemberPresence.inGame)
        .length;
    expect(find.text('此刻在线'), findsOneWidget);
    expect(find.text('游戏中 · $inGame'), findsOneWidget);
    expect(find.text('在线 · ${online.length - inGame}'), findsOneWidget);
    for (final member in online) {
      expect(
        find.byKey(ValueKey('official-fleet-online-${member.memberRef}')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search in the member list is not who is online', (
    tester,
  ) async {
    final module = createOfficialFleetMembersModule(
      InMemoryOfficialFleetMembersAdapter.forReview(),
    );
    addTearDown(module.dispose);
    await module.open('officialFleet:7');
    await module.search('Nova');
    await _pump(tester, OfficialFleetOnlinePane(members: module.projection));
    await tester.pump();
    expect(find.text('在线状态暂不可用'), findsOneWidget);
    expect(find.textContaining('游戏中 ·'), findsNothing);
  });

  testWidgets('without presence the column says so instead of guessing', (
    tester,
  ) async {
    final module = createOfficialFleetMembersModule(
      InMemoryOfficialFleetMembersAdapter(const <OfficialFleetMember>[]),
    );
    addTearDown(module.dispose);
    await module.open('officialFleet:7');
    await _pump(tester, OfficialFleetOnlinePane(members: module.projection));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('在线状态暂不可用'), findsOneWidget);
    expect(find.textContaining('游戏中 ·'), findsNothing);
  });

  // Option B (user 2026-10-29): the online column sits on the left like
  // community holo chat, collapses to a rail, and narrow windows keep the
  // rail instead of dropping the column.
  testWidgets('online column on the left; it collapses; narrow keeps a rail', (
    tester,
  ) async {
    Widget workspace() => OfficialFleetChatWorkspace(
      pinned: const Text('本周联合训练安排'),
      chat: const SizedBox.expand(key: Key('chat')),
      online: (_, {required collapsed, onToggle}) => GestureDetector(
        key: Key(collapsed ? 'rail' : 'online'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: const SizedBox.expand(),
      ),
    );
    await _pump(tester, workspace());
    await tester.pump();
    expect(find.byKey(const Key('official-fleet-chat-pinned')), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('PINNED'), findsNothing);
    expect(
      tester.getRect(find.text('本周联合训练安排')).bottom,
      lessThan(tester.getRect(find.byKey(const Key('chat'))).top),
    );
    final online = tester.getRect(find.byKey(const Key('online')));
    expect(
      online.right,
      lessThan(tester.getRect(find.byKey(const Key('chat'))).left),
    );
    expect(online.width, 240);
    await tester.tap(find.byKey(const Key('online')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('rail'))).width, 44);
    await tester.tap(find.byKey(const Key('rail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online')), findsOneWidget);
    await _pump(tester, workspace(), width: 800);
    await tester.pump();
    expect(find.byKey(const Key('rail')), findsOneWidget);
    expect(find.byKey(const Key('chat')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
