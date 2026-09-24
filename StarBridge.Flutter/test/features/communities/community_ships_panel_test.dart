import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

class _Port extends WorkspaceTestPort implements CommunityShipsPort {
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
    final count = query.text == 'missing' ? 0 : 25;
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': query.toPayload(),
      'targetRef': targetRef,
      'revision': 'b' * 64,
      'offset': offset,
      'totalCount': 25,
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

Future<void> _openShips(WidgetTester tester, _Port port, Locale locale) async {
  await tester.pumpWidget(host(port, locale));
  await tester.pumpAndSettle();
  final entry = find.byKey(const ValueKey('community-section-ships'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.byType(CommunityShipsPanel), findsOneWidget);
}

void main() {
  setUpAll(loadFonts);
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
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(port.requests.last.offset, 20);
      expect(port.requests.last.revision, 'b' * 64);
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
      await tester.ensureVisible(find.byType(DropdownButton<String>).last);
      await tester.tap(find.byType(DropdownButton<String>).last);
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
