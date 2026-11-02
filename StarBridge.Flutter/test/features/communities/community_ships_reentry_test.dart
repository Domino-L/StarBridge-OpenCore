// Returning to the ships page (user 2026-10-31): what was read stays on screen,
// the whole library is not read again, and the right column keeps its ship.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_pane.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import '../friends/social_layout_test.dart' show app, loadFonts;
import 'community_ships_test.dart' show shipRow;

final _target = 'a' * 32;
final _revision = 'b' * 64;

final class _Port implements CommunityShipsPort {
  _Port(this.count);
  int count;
  String revision = _revision;
  final reads = <int>[];
  bool failing = false;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads.add(offset);
    if (failing) throw const CommunityFailure('unavailable');
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'targetRef': targetRef,
      'revision': this.revision,
      'queryVersion': 2,
      'query': (query ?? CommunityShipQuery()).toPayload(),
      'offset': offset,
      'totalCount': count,
      'matchedCount': count,
      'next': offset + 20 < count ? offset + 20 : null,
      'ships': List.generate(
        (count - offset).clamp(0, 20),
        (i) => shipRow()
          ..['shipRef'] = (offset + i + 1).toRadixString(16).padLeft(32, '0'),
      ),
    });
  }

}

Future<void> _enter(
  WidgetTester tester,
  _Port port,
  CommunityShipsController model,
) async {
  await tester.pumpWidget(
    app(
      Scaffold(
        body: CommunityShipsPanel(
          port: port,
          targetRef: _target,
          name: 'Fleet',
          onBack: () {},
          controller: model,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(app(const SizedBox()));
  await tester.pump();
}

void main() {
  setUpAll(loadFonts);

  late _Port port;
  late CommunityShipsController model;
  late DateTime now;

  Future<void> firstVisit(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _enter(tester, port, model);
    await tester.pumpAndSettle();
    expect(find.text('已显示 55 / 55 艘'), findsOneWidget);
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 31, 12);
    port = _Port(55);
    model = CommunityShipsController(port, _target, now: () => now);
    addTearDown(model.dispose);
  });

  testWidgets('returning keeps every page, not only the last one read', (
    tester,
  ) async {
    await firstVisit(tester);
    await _leave(tester);
    await _enter(tester, port, model);
    expect(find.text('已显示 55 / 55 艘'), findsOneWidget);
    expect(find.text('已显示 15 / 55 艘'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('已显示 55 / 55 艘'), findsOneWidget);
  });

  testWidgets('returning to an unchanged library reads one page', (
    tester,
  ) async {
    await firstVisit(tester);
    await _leave(tester);
    now = now.add(const Duration(minutes: 5));
    port.reads.clear();
    await _enter(tester, port, model);
    expect(find.text('正在读取全库统计…'), findsNothing);
    await tester.pumpAndSettle();
    expect(port.reads, [0]);
    expect(find.text('正在读取全库统计…'), findsNothing);
  });

  testWidgets('the right column still shows its ship after returning', (
    tester,
  ) async {
    await firstVisit(tester);
    final selected = model.selectedShipRef;
    expect(selected, isNotNull);
    expect(find.byType(CommunityShipDetailPane), findsOneWidget);
    await _leave(tester);
    await _enter(tester, port, model);
    await tester.pumpAndSettle();
    expect(model.selectedShipRef, selected);
    expect(find.byType(CommunityShipDetailPane), findsOneWidget);
    expect(find.text('点一艘舰船，在这里查看详情。'), findsNothing);
  });

  testWidgets('a changed library replaces the summary only when read', (
    tester,
  ) async {
    await firstVisit(tester);
    await _leave(tester);
    now = now.add(const Duration(minutes: 5));
    port
      ..revision = 'e' * 64
      ..count = 56;
    await _enter(tester, port, model);
    expect(find.text('正在读取全库统计…'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('正在读取全库统计…'), findsNothing);
    expect(find.text('已显示 56 / 56 艘'), findsOneWidget);
    expect(model.statistics!.ships, hasLength(56));
    expect(model.pages.map((p) => p.revision).toSet(), {'e' * 64});
  });

  testWidgets('new content with the same total still reads the summary', (
    tester,
  ) async {
    await firstVisit(tester);
    await _leave(tester);
    now = now.add(const Duration(minutes: 5));
    port.revision = 'e' * 64;
    await _enter(tester, port, model);
    await tester.pumpAndSettle();
    expect(find.text('已显示 55 / 55 艘'), findsOneWidget);
    expect(model.statistics!.revision, 'e' * 64);
    expect(model.pages.map((p) => p.revision).toSet(), {'e' * 64});
  });

  testWidgets('a failed quiet read of the summary offers the retry', (
    tester,
  ) async {
    await firstVisit(tester);
    final held = model.statistics!;
    final first = await port.readShips(_target);
    port.failing = true;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CommunityShipStatisticsPanel(
            port: port,
            targetRef: _target,
            culture: 'zh-CN',
            firstPage: first,
            initial: CommunityShipStatistics(held.ships, revision: 'f' * 64),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法完成全库统计，请重试。'), findsOneWidget);
    expect(
      find.byKey(const Key('community-ship-statistics-retry')),
      findsOneWidget,
    );
  });

  testWidgets('invalidation forgets what was held', (tester) async {
    await firstVisit(tester);
    await _leave(tester);
    model.invalidate();
    expect(model.pages, isEmpty);
    expect(model.statistics, isNull);
  });

  test('a held inventory is only used for its own culture', () async {
    final other = CommunityShipsController(_Port(1), _target);
    addTearDown(other.dispose);
    other.holdStatistics(CommunityShipStatistics(const []), 'zh-CN');
    expect(other.statisticsFor('zh-CN'), isNotNull);
    expect(other.statisticsFor('en'), isNull);
  });
}
