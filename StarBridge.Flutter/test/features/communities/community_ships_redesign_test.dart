// The ships page redo (user decision 2026-10-29, option D): the summary
// strip, filter counts, the three views the organization remembers, pages
// that accumulate on scroll, and the side column on wide windows.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_pane.dart';
import 'package:starbridge_flutter/features/communities/community_ship_row_surface.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

const _target = '00000000000000000000000000000001';

Future<ExampleCommunities> _open(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final port = ExampleCommunities();
  addTearDown(port.close);
  await tester.pumpWidget(
    host(port, const Locale('zh', 'CN'), target: _target),
  );
  await tester.pumpAndSettle();
  final entry = find.byKey(const ValueKey('community-section-ships'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.byType(CommunityShipsPanel), findsOneWidget);
  return port;
}

Iterable<CommunityShipRowSurface> _selected(WidgetTester tester) => tester
    .widgetList<CommunityShipRowSurface>(find.byType(CommunityShipRowSurface))
    .where((s) => s.selected);

void main() {
  setUpAll(loadFonts);

  testWidgets('summary strip, counted filters and the side column at 1600', (
    tester,
  ) async {
    await _open(tester, 1600);
    expect(
      find.byKey(const ValueKey('community-ship-statistics')),
      findsOneWidget,
    );
    expect(find.text('待确认'), findsNothing);
    // Filter chips carry the full inventory's counts.
    expect(find.text('全部舰船 25'), findsOneWidget);
    // Wide: the side column shows a ship from the start, never placeholders,
    // and details never open a dialog.
    expect(find.byKey(const ValueKey('community-ships-side')), findsOneWidget);
    expect(find.byType(CommunityShipDetailPane), findsOneWidget);
    expect(find.byType(CommunityShipDetailDialog), findsNothing);
    expect(_selected(tester).length, 1);
    for (final view in ['owners', 'list', 'cards']) {
      await tester.tap(find.byKey(ValueKey('community-ships-view-$view')));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityShipDetailPane), findsOneWidget);
      expect(find.text('调度'), findsNothing);
      expect(find.text('即将开始的行动'), findsNothing);
    }
    final details = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          '${(w.key as ValueKey).value}'.startsWith('community-ship-details-'),
    );
    await tester.tap(details.first);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipDetailDialog), findsNothing);
    expect(find.byType(CommunityShipDetailPane), findsOneWidget);
    expect(_selected(tester).length, 1);
    final first = _selected(tester).single;
    // Right arrow walks to the next ship.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_selected(tester).length, 1);
    expect(identical(_selected(tester).single, first), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow windows keep the dialog and drop the side column', (
    tester,
  ) async {
    await _open(tester, 1000);
    expect(find.byKey(const ValueKey('community-ships-side')), findsNothing);
    final details = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          '${(w.key as ValueKey).value}'.startsWith('community-ship-details-'),
    );
    await tester.ensureVisible(details.first);
    await tester.tap(details.first);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipDetailDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-ship-detail-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the owner view groups the whole inventory and is remembered', (
    tester,
  ) async {
    await _open(tester, 1600);
    await tester.tap(find.byKey(const ValueKey('community-ships-view-owners')));
    await tester.pumpAndSettle();
    final groups = find.byKey(const ValueKey('community-ships-owner-groups'));
    expect(groups, findsOneWidget);
    final tiles = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          '${(w.key as ValueKey).value}'.startsWith(
            'community-ships-owner-tile-',
          ),
    );
    expect(tiles, findsWidgets);
    // Picking a tile opens the details in the side column.
    await tester.tap(tiles.first);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipDetailPane), findsOneWidget);
    // Leaving and returning keeps the owner view (the organization remembers).
    final members = find.byKey(const ValueKey('community-section-members'));
    await tester.ensureVisible(members);
    await tester.tap(members);
    await tester.pumpAndSettle();
    final ships = find.byKey(const ValueKey('community-section-ships'));
    await tester.ensureVisible(ships);
    await tester.tap(ships);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('community-ships-owner-groups')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scrolling to the end loads the next page without replacing', (
    tester,
  ) async {
    await _open(tester, 1600);
    final list = find.descendant(
      of: find.byKey(const Key('community-ships-list')),
      matching: find.byType(Scrollable),
    );
    for (
      var i = 0;
      i < 12 && find.textContaining('25 / 25').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('25 / 25'), findsOneWidget);
    expect(find.byKey(const Key('community-ships-next')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
