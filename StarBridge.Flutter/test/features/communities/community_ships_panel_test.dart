import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/ships/ship_classification_tag.dart';
import 'package:starbridge_flutter/features/communities/community_ship_vehicle_icon.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_catalog_ship_image.dart';
import 'package:starbridge_flutter/features/communities/community_ship_banner.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

class _Port extends WorkspaceTestPort implements CommunityShipsPort {
  int total = 25;
  Completer<void>? gate;
  final requests =
      <({int offset, String? revision, CommunityShipQuery query})>[];
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    requests.add((offset: offset, revision: revision, query: query!));
    await gate?.future;
    final total = this.total;
    final count = query.text == 'missing' ? 0 : 25;
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': query.toPayload(),
      'targetRef': targetRef,
      'revision': (query.filter == 'all' ? 'b' : 'c') * 64,
      'offset': offset,
      'totalCount': total,
      'matchedCount': count,
      'next': count > 20 && offset == 0 ? 20 : null,
      'ships': List.generate(
        count == 0
            ? 0
            : offset == 0
            ? 20
            : 5,
        (i) => shipRow()
          ..['shipRef'] = (offset + i).toRadixString(16).padLeft(32, '0')
          ..['ownerHasAvatar'] = false
          ..['displayName'] = 'Shared ship ${offset + i + 1}',
      ),
    });
  }
}

Future<void> _openShips(
  WidgetTester tester,
  _Port port,
  Locale locale, {
  bool list = true,
}) async {
  await tester.pumpWidget(host(port, locale));
  await tester.pumpAndSettle();
  final entry = find.byKey(const ValueKey('community-section-ships'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.byType(CommunityShipsPanel), findsOneWidget);
  // These checks cover the list view; cards have their own tests.
  if (!list) return;
  await tester.tap(find.byKey(const ValueKey('community-ships-view-list')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  testWidgets('cards are the default and keep every field and action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final port = _Port();
    addTearDown(port.changes.close);
    await _openShips(tester, port, const Locale('en'), list: false);
    String ref(int i) => i.toRadixString(16).padLeft(32, '0');
    expect(find.byType(CommunityShipColumnHeader), findsNothing);
    final first = find.byKey(ValueKey('community-ship-card-image-${ref(0)}'));
    final second = find.byKey(ValueKey('community-ship-card-image-${ref(1)}'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    // Side by side in one grid row.
    // The selected first card's frame may shift it by half a pixel.
    expect(
      tester.getRect(second).top,
      moreOrLessEquals(tester.getRect(first).top, epsilon: 1),
    );
    expect(
      tester.getRect(second).left,
      greaterThan(tester.getRect(first).right),
    );
    // The card art fills its frame, as the approved preview.
    final image = tester.widget<CommunityCatalogShipImage>(
      find.descendant(
        of: first,
        matching: find.byType(CommunityCatalogShipImage),
      ),
    );
    expect(image.compact, isTrue);
    // The preview card (user 2026-10-29): name over the art, three tags, the
    // owner, the price and the details action; no labelled cells, no glyph.
    final card = find.byKey(ValueKey('community-ship-card-${ref(0)}'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(CommunityShipBanner)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byType(CommunityShipVehicleIcon),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byType(ShipClassificationTag)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: card, matching: find.text('Shared ship 1')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('community-ship-details-${ref(0)}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('community-ships-view-list')));
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    expect(find.byType(CommunityShipColumnHeader), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-ships-view-cards')));
    await tester.pumpAndSettle();
    expect(first, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('background ship polling does not show a loading bar', (
    tester,
  ) async {
    final port = _Port();
    addTearDown(port.changes.close);
    await _openShips(tester, port, const Locale('en'));
    port.gate = Completer();
    final before = port.requests.length;
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(port.requests.length, before + 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    port.gate!.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a filter reads its list once; statistics stay and do not reread', (
    tester,
  ) async {
    final port = _Port();
    addTearDown(port.changes.close);
    await _openShips(tester, port, const Locale('zh', 'CN'));
    final reads = port.requests.length;
    await tester.tap(find.byKey(const ValueKey('community-ship-filter-large')));
    await tester.pump();
    expect(find.text('正在读取全库统计…'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('正在读取全库统计…'), findsNothing);
    expect(port.requests.length, reads + 1, reason: 'Only the list.');
    expect(port.requests.last.query.filter, 'large');
    expect(port.requests.last.offset, 0);
    await tester.tap(find.byKey(const ValueKey('community-ship-filter-all')));
    await tester.pumpAndSettle();
    expect(port.requests.length, reads + 2, reason: 'Back again, the same.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('statistics reread when the inventory really changed', (
    tester,
  ) async {
    final port = _Port();
    addTearDown(port.changes.close);
    await _openShips(tester, port, const Locale('zh', 'CN'));
    final reads = port.requests.length;
    port.total = 26;
    await tester.tap(find.byKey(const ValueKey('community-ship-filter-large')));
    await tester.pumpAndSettle();
    final later = port.requests.skip(reads).toList();
    expect(later.first.query.filter, 'large');
    expect(
      later.skip(1).where((read) => read.query.filter == 'all'),
      isNotEmpty,
      reason: 'The count moved, whatever the filter shows.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning to ships preserves its page without refetching', (
    tester,
  ) async {
    final port = _Port();
    addTearDown(port.changes.close);
    await _openShips(tester, port, const Locale('zh', 'CN'));
    final reads = port.requests.length;
    await tester.tap(find.byKey(const ValueKey('community-section-members')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 16));
    expect(port.requests.length, reads, reason: 'Hidden ships must not poll.');
    await tester.tap(find.byKey(const ValueKey('community-section-ships')));
    await tester.pumpAndSettle();
    expect(
      port.requests.length,
      reads,
      reason: 'Navigation must not redownload the inventory.',
    );
    expect(find.text('Shared ship 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      testWidgets(
        'Ships ${locale.toLanguageTag()} fits $width with real workspace entry and avatar menu',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final port = _Port();
          addTearDown(port.changes.close);
          await _openShips(tester, port, locale);
          expect(find.text('Shared ship 1'), findsOneWidget);
          expect(port.requests.first.query.sort, 'spec');
          expect(
            port.requests.first.query.culture,
            locale.languageCode == 'en'
                ? 'en-US'
                : locale.countryCode == 'TW'
                ? 'zh-TW'
                : 'zh-CN',
          );
          expect(tester.takeException(), isNull);
          final statistics = find.byKey(
            const ValueKey('community-ship-statistics'),
          );
          expect(statistics, findsOneWidget);
          final expand = find.byKey(
            const ValueKey('community-ship-statistics-expand'),
          );
          await tester.ensureVisible(expand);
          await tester.tap(expand);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('ship-distribution-table-toggle')),
            findsOneWidget,
          );
          final dialog = find.byKey(
            const ValueKey('community-statistics-dialog'),
          );
          expect(dialog, findsOneWidget);
          await tester.tap(
            find.descendant(of: dialog, matching: find.byType(TextButton)).last,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(UserAvatarMenu).first);
          await tester.tap(find.byType(UserAvatarMenu).first);
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsWidgets);
          port.changes.add(null);
          await tester.pumpAndSettle();
          expect(find.text('Shared ship 1'), findsNothing);
          expect(find.byType(MenuItemButton), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'Search, sort, paging, no-match reset and back preserve server query',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _Port();
      addTearDown(port.changes.close);
      await _openShips(tester, port, const Locale('en'));
      // Pages accumulate and load by themselves: page 1 stays.
      expect(find.byKey(const Key('community-ships-next')), findsNothing);
      await tester.pumpAndSettle();
      expect(port.requests.last.offset, 20);
      expect(port.requests.last.revision, 'b' * 64);
      expect(find.text('Shared ship 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Shared ship 21'),
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('community-ships-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Shared ship 21'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(port.requests.last.offset, 0);
      expect(port.requests.last.revision, isNull);
      expect(find.textContaining('No matching ships'), findsOneWidget);
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(port.requests.last.query.text, isEmpty);
      final sortControl = find.byKey(
        const ValueKey('community-ships-sort-control'),
      );
      await tester.ensureVisible(sortControl);
      await tester.tap(sortControl);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ship name').last);
      await tester.pumpAndSettle();
      expect(port.requests.last.query.sort, 'name');
      expect(port.requests.last.query.descending, isFalse);
      await tester.ensureVisible(find.text('Back to organization'));
      await tester.tap(find.text('Back to organization'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityShipsPanel), findsNothing);
      expect(find.text('Organization A'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Render shared fleet without launching an acceptance client', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _Port();
    addTearDown(port.changes.close);
    await _openShips(tester, port, const Locale('zh', 'CN'));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('workspace-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = File('build/community-ships-review.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
