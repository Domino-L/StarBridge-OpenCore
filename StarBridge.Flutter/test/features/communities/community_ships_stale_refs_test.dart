// User report 2026-11-15: on entering a fleet's ships (or after a while there)
// every ship picked said "舰船库已更新"; refreshing once fixed it. An older
// Host renamed ship references after five minutes, and the Relay's revision
// moves with the owners' presence (until r50). These use only interfaces that
// existed before the fix, so they run red on the base.
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;

final _target = 'a' * 32;

final class StaleRefsPort implements CommunityShipsPort {
  StaleRefsPort(this.count);
  final int count;

  /// A new epoch is an older Host renaming the same rows.
  int refEpoch = 0;
  String revision = 'b' * 64;

  /// Ships added at the top of the list, pushing the others down.
  int prepended = 0;
  bool online = true;

  /// Reads without a revision fail like a dropped connection.
  bool unpinnedDown = false;
  final removed = <int>{};
  final reads = <(int, String?)>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get shipsAvailable => true;

  String refFor(int ship) =>
      (refEpoch * 1000 + ship + 1).toRadixString(16).padLeft(32, '0');

  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads.add((offset, revision));
    if (unpinnedDown && revision == null) {
      throw const CommunityFailure('unavailable');
    }
    // Like the Flutter bridge: a later page is only read against a revision.
    if (offset > 0 && revision == null) {
      throw const CommunityFailure('dataInvalid');
    }
    // Like the Relay: a pinned revision that moved is a 409, which the Host
    // reports as shipsChanged.
    if (revision != null && revision != this.revision) {
      throw const CommunityFailure('shipsChanged');
    }
    final ships = [
      for (var i = 0; i < prepended; i++) 900 + i,
      for (var i = 0; i < count; i++)
        if (!removed.contains(i)) i,
    ];
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'targetRef': targetRef,
      'revision': this.revision,
      'queryVersion': 2,
      'query': (query ?? CommunityShipQuery()).toPayload(),
      'offset': offset,
      'totalCount': ships.length,
      'matchedCount': ships.length,
      'next': offset + 20 < ships.length ? offset + 20 : null,
      'ships': [
        for (final i in ships.skip(offset).take(20))
          shipRow()
            ..['shipRef'] = refFor(i)
            ..['code'] = 'fixture-ship-$i'
            ..['displayName'] = 'Ship $i'
            ..['ownerOnline'] = online
            ..['ownerLiveStatus'] = online ? 'InGame' : 'Offline',
      ],
    });
  }
}

void main() {
  var clock = DateTime.utc(2026, 11, 15, 12);
  setUp(() => clock = DateTime.utc(2026, 11, 15, 12));

  Future<CommunityShipsController> list(StaleRefsPort port) async {
    final model = CommunityShipsController(port, _target, now: () => clock);
    addTearDown(model.dispose);
    await model.load();
    return model;
  }

  Future<CommunityShipDetailController> detail(
    StaleRefsPort port,
    CommunityShipsPage page,
    String shipRef,
  ) async {
    final model = CommunityShipDetailController(port, page, shipRef);
    addTearDown(model.dispose);
    await model.load();
    return model;
  }

  test('returning to renamed references takes them, same revision', () async {
    final port = StaleRefsPort(3);
    final model = await list(port);
    final old = model.pages.first.ships[1].shipRef;
    port.refEpoch++;
    clock = clock.add(const Duration(minutes: 6));
    await model.enter();
    expect(model.error, isNull);
    expect(model.pages.first.ships[1].shipRef, port.refFor(1));
    expect(model.pages.first.ships[1].shipRef, isNot(old));
  });

  test('an owner coming online shows, same revision', () async {
    final port = StaleRefsPort(3)..online = false;
    final model = await list(port);
    port.online = true;
    clock = clock.add(const Duration(minutes: 1));
    await model.enter();
    expect(model.error, isNull);
    expect(model.pages.first.ships.every((s) => s.ownerOnline), isTrue);
  });

  test('the first page is read without the old revision', () async {
    final port = StaleRefsPort(3);
    final held = (await list(port)).pages.first;
    port.revision = 'e' * 64;
    final model = await detail(port, held, held.ships[2].shipRef);
    expect(model.error, isNull);
    expect(model.ship?.code, 'fixture-ship-2');
  });

  test(
    'a later page whose revision moved is read again, then the ship',
    () async {
      final port = StaleRefsPort(45);
      final model = await list(port);
      await model.next();
      final held = model.page!;
      expect(held.offset, 20);
      port.revision = 'e' * 64;
      final shown = await detail(port, held, held.ships[3].shipRef);
      expect(shown.error, isNull);
      expect(shown.ship?.code, 'fixture-ship-23');
    },
  );

  test('a ship pushed to the next page is found there', () async {
    final port = StaleRefsPort(25);
    final held = (await list(port)).pages.first;
    final last = held.ships.last;
    port
      ..prepended = 1
      ..revision = 'e' * 64;
    final shown = await detail(port, held, last.shipRef);
    expect(shown.error, isNull);
    expect(shown.ship?.code, last.code);
  });

  test('a ship that really left still says the library changed', () async {
    final port = StaleRefsPort(3);
    final held = (await list(port)).pages.first;
    port.removed.add(1);
    final model = await detail(port, held, held.ships[1].shipRef);
    expect(model.error, 'shipsChanged');
    expect(model.ship, isNull);
  });

  test('a renamed reference is never guessed from a look-alike', () async {
    final port = StaleRefsPort(3);
    final held = (await list(port)).pages.first;
    port.refEpoch++;
    final model = await detail(port, held, held.ships[1].shipRef);
    expect(model.error, 'shipsChanged');
    expect(model.ship, isNull);
  });
}
