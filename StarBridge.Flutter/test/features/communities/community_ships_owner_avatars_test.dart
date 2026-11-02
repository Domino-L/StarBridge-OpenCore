// The owner view and the summary strip show the whole inventory, while the
// library reads 20 rows at a time. An owner whose only ship is on a later page
// still has an avatar (user report 2026-10-30, seen as a default icon).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_fleet_summary.dart';
import 'package:starbridge_flutter/features/communities/community_ship_avatar_access.dart';
import 'package:starbridge_flutter/features/communities/community_ship_card.dart';
import 'package:starbridge_flutter/features/communities/community_ship_owner_avatar.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort, mediaChunk;
import '../friends/social_layout_test.dart' show app, loadFonts, size;

final _target = 'a' * 32;
final _first = 'd' * 32;
final _later = 'f' * 32;
final _firstBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
final _laterBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
);

/// 20 rows of the first owner, then 5 of an owner only the second page shows.
final class _Library extends WorkspaceTestPort implements CommunityShipsPort {
  final mediaReads = <String>[];
  final pageReads = <int>[];
  final held = <String, Completer<void>>{};
  Object? laterFailure;
  bool laterHasAvatar = true;
  bool tooMany = false;
  @override
  bool get shipsAvailable => true;

  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    final shown = query ?? CommunityShipQuery();
    pageReads.add(offset);
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': shown.toPayload(),
      'targetRef': targetRef,
      'revision': 'b' * 64,
      'offset': offset,
      'next': offset == 0 ? 20 : null,
      'totalCount': tooMany ? CommunityFleetSummary.maximumShips + 1 : 25,
      'matchedCount': 25,
      'ships': List.generate(offset == 0 ? 20 : 5, (i) {
        final later = offset != 0;
        return shipRow()
          ..['shipRef'] = (offset + i).toRadixString(16).padLeft(32, '0')
          ..['ownerMemberRef'] = later ? _later : _first
          ..['ownerCallsign'] = later ? 'Later' : 'First'
          ..['ownerHasAvatar'] = !later || laterHasAvatar;
      }),
    });
  }

  Future<Map<String, Object?>> read(String member, int offset) async {
    mediaReads.add(member);
    await held[member]?.future;
    if (member == _later && laterFailure != null) throw laterFailure!;
    return mediaChunk(
      member == _later ? _laterBytes : _firstBytes,
      offset,
      kind: 'avatar',
      memberRef: member,
    );
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) => read(memberRef!, offset);
}

Future<List<CommunitySharedShip>> _inventory(_Library port) async {
  final query = CommunityShipQuery();
  return [
    ...(await port.readShips(_target, query: query)).ships,
    ...(await port.readShips(_target, offset: 20, query: query)).ships,
  ];
}

Future<void> _settled() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// Real image decoding finishes outside the fake clock and its progress
// indicator never settles.
Future<void> _settledPanel(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadFonts);

  group('controller', () {
    late _Library port;
    late CommunityShipsController model;
    setUp(() {
      port = _Library();
      model = CommunityShipsController(port, _target, mediaPort: port);
    });
    tearDown(() async {
      model.dispose();
      await port.changes.close();
    });

    test('an owner only on the second page gets an avatar', () async {
      await model.load();
      expect(model.avatar(_first), Uint8List.fromList(_firstBytes));
      expect(model.avatar(_later), isNull);
      model.showOwners(await _inventory(port));
      await _settled();
      expect(model.avatar(_later), Uint8List.fromList(_laterBytes));
      expect(model.avatar(_first), Uint8List.fromList(_firstBytes));
      expect(port.mediaReads.where((m) => m == _first), hasLength(1));
      expect(port.mediaReads.where((m) => m == _later), hasLength(1));
    });

    test('the inventory is held when it arrives during a page read', () async {
      await model.load();
      final inventory = await _inventory(port);
      final read = model.load();
      expect(model.busy, isTrue);
      model.showOwners(inventory);
      await read;
      await _settled();
      expect(model.avatar(_later), Uint8List.fromList(_laterBytes));
    });

    test('reading a later page keeps the owners already shown', () async {
      await model.load();
      model.showOwners(await _inventory(port));
      await _settled();
      await model.next();
      expect(model.page!.offset, 20);
      expect(model.avatar(_first), Uint8List.fromList(_firstBytes));
      expect(model.avatar(_later), Uint8List.fromList(_laterBytes));
    });

    test('without an inventory a later page keeps the rows above it', () async {
      await model.load();
      await model.next();
      expect(model.avatar(_first), Uint8List.fromList(_firstBytes));
      expect(model.avatar(_later), Uint8List.fromList(_laterBytes));
      // Starting over lists only the first page again.
      await model.load();
      expect(model.avatar(_first), Uint8List.fromList(_firstBytes));
      expect(model.avatar(_later), isNull);
    });

    test('the next page can start before the first avatars finish', () async {
      port.held[_first] = Completer<void>();
      final first = model.load();
      await _settled();
      expect(model.page!.offset, 0);
      expect(model.busy, isFalse);
      expect(model.avatarLoading(_first), isTrue);
      final second = model.next();
      await _settled();
      expect(model.page!.offset, 20);
      port.held[_first]!.complete();
      await Future.wait([first, second]);
      await _settled();
      expect(model.avatar(_first), Uint8List.fromList(_firstBytes));
      expect(model.avatar(_later), Uint8List.fromList(_laterBytes));
      expect(model.avatarLoading(_first), isFalse);
      expect(port.mediaReads.where((m) => m == _first), hasLength(1));
    });

    test('the inventory arriving on a later page still fills everyone', () async {
      await model.load();
      await model.next();
      model.showOwners(await _inventory(port));
      await _settled();
      expect(model.page!.offset, 20);
      expect(model.avatar(_first), Uint8List.fromList(_firstBytes));
      expect(model.avatar(_later), Uint8List.fromList(_laterBytes));
      expect(port.mediaReads.where((m) => m == _first), hasLength(1));
      expect(port.mediaReads.where((m) => m == _later), hasLength(1));
    });

    test('a refresh waits for the inventory read beside the page read', () async {
      port.held[_first] = Completer<void>();
      port.held[_later] = Completer<void>();
      final read = model.load();
      await _settled();
      model.showOwners(await _inventory(port));
      await _settled();
      port.held[_first]!.complete();
      await read;
      await _settled();
      expect(model.avatarLoading(_later), isTrue);
      await model.refreshVisible();
      port.held[_later]!.complete();
      await _settled();
      expect(model.avatar(_later), Uint8List.fromList(_laterBytes));
      expect(model.avatarLoading(_later), isFalse);
    });

    test('a lapsed reference off the page does not take the page down', () async {
      await model.load();
      port.laterFailure = const CommunityFailure('refreshRequired');
      model.showOwners(await _inventory(port));
      await _settled();
      expect(model.avatar(_later), isNull);
      expect(model.invalidated, isFalse);
      expect(model.error, isNull);
      expect(model.mediaFailed, isFalse);
      expect(model.page, isNotNull);
      expect(model.avatarLoading(_later), isFalse);
      // On its own page the same answer still means the rows are stale.
      await model.next();
      expect(model.invalidated, isTrue);
    });

    test('the page is the newer answer for an owner it shows', () async {
      await model.load();
      model.showOwners(await _inventory(port));
      await _settled();
      port.laterHasAvatar = false;
      await model.next();
      expect(model.avatar(_later), isNull);
    });

    test('an account change forgets the inventory', () async {
      await model.load();
      model.showOwners(await _inventory(port));
      await _settled();
      port.changes.add(null);
      expect(model.avatar(_later), isNull);
      expect(model.avatar(_first), isNull);
    });
  });

  group('panel', () {
    Future<void> check(
      WidgetTester tester,
      _Library port,
      CommunityShipsPanel panel,
    ) async {
      size(tester, const Size(1600, 1000));
      await tester.pumpWidget(app(panel));
      await _settledPanel(tester);
      // The owner view reads no further pages itself: only the statistics read
      // reached the page this owner is on.
      expect(port.pageReads.where((offset) => offset == 20), hasLength(1));
      final owner = tester
          .widgetList<CommunityShipOwnerAvatar>(
            find.byType(CommunityShipOwnerAvatar),
          )
          .where((a) => a.ship.ownerMemberRef == _later)
          .first;
      expect(owner.bytes, Uint8List.fromList(_laterBytes));
      // The strip draws the portrait, not the name's first letter.
      final strip = find.byKey(const ValueKey('community-ship-statistics'));
      expect(
        tester
            .widgetList<CommunityWorkspaceImage>(
              find.descendant(
                of: strip,
                matching: find.byType(CommunityWorkspaceImage),
              ),
            )
            .map((image) => image.bytes)
            .toList(),
        anyElement(orderedEquals(_laterBytes)),
      );
      expect(
        find.descendant(of: strip, matching: find.text('L')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      panel.controller!.dispose();
      await port.changes.close();
    }

    testWidgets('cards keep earlier owners after the next page loads itself', (
      tester,
    ) async {
      // Too large for statistics, so only the pages themselves name owners.
      final port = _Library()..tooMany = true;
      size(tester, const Size(1600, 1000));
      await tester.pumpWidget(
        app(
          CommunityShipsPanel(
            port: port,
            targetRef: _target,
            name: 'Synthetic organization',
            onBack: () {},
          ),
        ),
      );
      await _settledPanel(tester);
      expect(port.pageReads, contains(20));
      final first = tester
          .widgetList<CommunityShipCard>(find.byType(CommunityShipCard))
          .firstWhere((card) => card.ship.ownerMemberRef == _first);
      expect(first.avatarBytes, Uint8List.fromList(_firstBytes));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await port.changes.close();
    });

    testWidgets('owner view and strip through community media', (tester) async {
      final port = _Library();
      await check(
        tester,
        port,
        CommunityShipsPanel(
          port: port,
          targetRef: _target,
          name: 'Synthetic organization',
          onBack: () {},
          controller: CommunityShipsController(port, _target, mediaPort: port)
            ..viewMode = 'owners',
        ),
      );
    });

    testWidgets('owner view and strip through the main fleet reader', (
      tester,
    ) async {
      final port = _Library();
      final access = CommunityShipAvatarAccess(
        read: (target, member, {required offset, version}) =>
            port.read(member, offset),
      );
      await check(
        tester,
        port,
        CommunityShipsPanel(
          port: port,
          targetRef: _target,
          name: 'Synthetic fleet',
          onBack: () {},
          avatarAccess: access,
          controller: CommunityShipsController(
            port,
            _target,
            avatarAccess: access,
          )..viewMode = 'owners',
        ),
      );
    });
  });
}
