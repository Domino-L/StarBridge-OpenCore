// User report 2026-11-15, the wiring around a ship found again on another page
// or revision: the list is told, the selection follows the ship across every
// held page, and a forced refresh reads every held page again.
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_locate.dart';

import 'community_ships_stale_refs_test.dart' show StaleRefsPort;

final _target = 'a' * 32;

void main() {
  Future<CommunityShipsController> list(StaleRefsPort port) async {
    final model = CommunityShipsController(port, _target);
    addTearDown(model.dispose);
    await model.load();
    return model;
  }

  test('only a ship found again tells the list it is out of date', () async {
    final port = StaleRefsPort(45);
    final model = await list(port);
    await model.next();
    final held = model.page!;
    var relocated = 0;
    final direct = CommunityShipDetailController(
      port,
      held,
      held.ships[0].shipRef,
      onRelocated: () => relocated++,
    );
    addTearDown(direct.dispose);
    await direct.load();
    expect(direct.error, isNull);
    expect(relocated, 0);
    port.revision = 'e' * 64;
    final found = CommunityShipDetailController(
      port,
      held,
      held.ships[1].shipRef,
      onRelocated: () => relocated++,
    );
    addTearDown(found.dispose);
    await found.load();
    expect(found.error, isNull);
    expect(relocated, 1);
    expect(found.page.revision, 'e' * 64);
    expect(found.shipRef, held.ships[1].shipRef);
    // Reading it again uses the page it was found on: no second search.
    final reads = port.reads.length;
    await found.load(background: true);
    expect(found.error, isNull);
    expect(port.reads.length, reads + 1);
  });

  test('the selection follows the ship to another held page', () async {
    final port = StaleRefsPort(25);
    final model = await list(port);
    final held = model.pages.first;
    final selected = held.ships[5].shipRef;
    port
      ..prepended = 18
      ..revision = 'e' * 64;
    final first = await port.readShips(_target, query: held.query);
    final second = await port.readShips(
      _target,
      offset: 20,
      revision: first.revision,
      query: held.query,
    );
    final after = communityShipSelectionAcross([first, second], held, selected);
    expect(after?.gone, isFalse);
    expect(after?.page.offset, 20);
    // One page alone never decides: the first page lacks it, the second has it.
    expect(communityShipSelectionAfter(first, held, selected)?.gone, isTrue);
    port.removed.add(5);
    final without = await port.readShips(_target, query: held.query);
    final gone = communityShipSelectionAcross([without], held, selected);
    expect(gone?.gone, isTrue);
  });

  test('a deep page is read again in its own place first', () async {
    final port = StaleRefsPort(130);
    final model = await list(port);
    while (model.page!.next != null) {
      await model.next();
    }
    final held = model.page!;
    expect(held.offset, 120);
    port.revision = 'e' * 64;
    final reads = port.reads.length;
    final shown = CommunityShipDetailController(
      port,
      held,
      held.ships[4].shipRef,
    );
    addTearDown(shown.dispose);
    await shown.load();
    expect(shown.error, isNull);
    expect(shown.ship?.code, 'fixture-ship-124');
    // The refused read, the first page, its own place, and the ship.
    expect(port.reads.skip(reads).map((r) => r.$1), [120, 0, 120, 120]);
  });

  test('a deep ship pushed to the next page is found there', () async {
    final port = StaleRefsPort(141);
    final model = await list(port);
    while (model.page!.offset < 120) {
      await model.next();
    }
    final held = model.page!;
    final last = held.ships.last;
    port
      ..prepended = 1
      ..revision = 'e' * 64;
    final shown = CommunityShipDetailController(port, held, last.shipRef);
    addTearDown(shown.dispose);
    await shown.load();
    expect(shown.error, isNull);
    expect(shown.ship?.code, last.code);
    expect(shown.page.offset, 140);
  });

  test('a failed read while finding the ship is not "changed"', () async {
    // Review R4 P2: the ship is still there; the read failed. Retry, not a
    // library refresh.
    final port = StaleRefsPort(45);
    final model = await list(port);
    await model.next();
    final held = model.page!;
    port
      ..revision = 'e' * 64
      ..unpinnedDown = true;
    final shown = CommunityShipDetailController(
      port,
      held,
      held.ships[2].shipRef,
    );
    addTearDown(shown.dispose);
    await shown.load();
    expect(shown.error, 'unavailable');
    expect(shown.invalidated, isFalse);
  });

  test('a forced refresh reads the held pages again', () async {
    final port = StaleRefsPort(45);
    final model = await list(port);
    await model.next();
    final reads = port.reads.length;
    await model.refreshVisible();
    expect(port.reads.length, reads + 1, reason: 'unchanged: one page');
    await model.refreshVisible(force: true);
    expect(port.reads.length, reads + 3, reason: 'forced: both pages');
    expect(model.pages.map((p) => p.offset), [0, 20]);
  });
}
