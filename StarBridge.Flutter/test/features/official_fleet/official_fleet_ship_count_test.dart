import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ship_count.dart';

import '../communities/community_ships_test.dart' show shipRow;

const _target = 'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0';
const _culture = 'zh-CN';

final class _Port implements CommunityShipsPort, CommunityShipsRefreshPort {
  _Port([this.total = 3]);
  int total;
  bool available = true;
  Object? failure;
  Completer<void>? gate;
  var reads = 0;
  final queries = <CommunityShipQuery?>[];
  final offsets = <int>[];
  final changes = StreamController<void>.broadcast();
  final refreshes = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Stream<void> get shipRefreshes => refreshes.stream;
  @override
  bool get shipsAvailable => available;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads++;
    queries.add(query);
    offsets.add(offset);
    final answer = total;
    await gate?.future;
    if (failure != null) throw failure!;
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': query!.toPayload(),
      'targetRef': targetRef,
      'revision': 'b' * 64,
      'offset': offset,
      'next': null,
      'totalCount': answer,
      'matchedCount': answer,
      'ships': [
        for (var i = 1; i <= answer; i++)
          {...shipRow(), 'shipRef': i.toRadixString(16).padLeft(32, '0')},
      ],
    });
  }
}

void main() {
  late DateTime now;
  late OfficialFleetShipCount model;
  var notified = 0;
  setUp(() {
    now = DateTime.utc(2026, 11, 2, 8);
    notified = 0;
    model = OfficialFleetShipCount(now: () => now)
      ..addListener(() => notified++);
  });
  tearDown(() => model.dispose());

  test('reads the first page once, however often the rail builds', () async {
    final port = _Port();
    model.load(port, _target, _culture);
    expect(model.reading, isTrue);
    expect(model.count, isNull);
    model.load(port, _target, _culture);
    await pumpEventQueue();
    model.load(port, _target, _culture);
    await pumpEventQueue();
    expect(model.count, 3);
    expect(model.reading, isFalse);
    expect(port.reads, 1);
    expect(port.offsets, [0]);
    expect(port.queries.single?.culture, _culture);
    expect(notified, 1);
  });

  test('a known zero is a count, not an unknown', () async {
    model.load(_Port(0), _target, _culture);
    await pumpEventQueue();
    expect(model.count, 0);
    expect(model.failed, isFalse);
  });

  test('no target or no ships capability sends nothing', () async {
    final port = _Port()..available = false;
    model.load(port, _target, _culture);
    model.load(_Port(), null, _culture);
    model.load(null, _target, _culture);
    await pumpEventQueue();
    expect(port.reads, 0);
    expect(model.count, isNull);
    expect(model.reading, isFalse);
  });

  test('a failed read says so and is not retried on every build', () async {
    final port = _Port()..failure = StateError('offline');
    model.load(port, _target, _culture);
    await pumpEventQueue();
    expect(model.failed, isTrue);
    expect(model.count, isNull);
    model.load(port, _target, _culture);
    await pumpEventQueue();
    expect(port.reads, 1);
    now = now.add(OfficialFleetShipCount.revisitAge);
    port.failure = null;
    model
      ..left()
      ..load(port, _target, _culture);
    await pumpEventQueue();
    expect(port.reads, 2);
    expect(model.failed, isFalse);
    expect(model.count, 3);
  });

  test('no timer: staying on the page never reads again', () async {
    final port = _Port();
    model.load(port, _target, _culture);
    await pumpEventQueue();
    now = now.add(const Duration(hours: 8));
    model.load(port, _target, _culture);
    await pumpEventQueue();
    expect(port.reads, 1);
  });

  test('a quick return keeps the count, a later visit reads again', () async {
    final port = _Port();
    model.load(port, _target, _culture);
    await pumpEventQueue();
    now = now.add(
      OfficialFleetShipCount.revisitAge - const Duration(seconds: 1),
    );
    model
      ..left()
      ..load(port, _target, _culture);
    expect(port.reads, 1);
    now = now.add(const Duration(seconds: 1));
    model.load(port, _target, _culture);
    expect(port.reads, 1, reason: 'That return was already spent');
    port
      ..total = 5
      ..gate = Completer<void>();
    model
      ..left()
      ..load(port, _target, _culture);
    await pumpEventQueue();
    expect(port.reads, 2);
    expect(model.count, 3);
    port.gate!.complete();
    await pumpEventQueue();
    expect(model.count, 5);
  });

  test('a later failure keeps the count already shown', () async {
    final port = _Port();
    model.load(port, _target, _culture);
    await pumpEventQueue();
    now = now.add(OfficialFleetShipCount.revisitAge);
    port.failure = StateError('offline');
    model
      ..left()
      ..load(port, _target, _culture);
    await pumpEventQueue();
    expect(model.count, 3);
    expect(model.failed, isTrue);
  });

  test('an invalidated scope drops the count and its pending read', () async {
    final port = _Port();
    model.load(port, _target, _culture);
    await pumpEventQueue();
    port
      ..total = 9
      ..gate = Completer<void>();
    now = now.add(OfficialFleetShipCount.revisitAge);
    model
      ..left()
      ..load(port, _target, _culture);
    port.changes.add(null);
    await pumpEventQueue();
    expect(model.count, isNull);
    expect(model.reading, isFalse);
    port.gate!.complete();
    await pumpEventQueue();
    expect(model.count, isNull, reason: 'The retired read must not land');
    port.gate = null;
    model.load(port, _target, _culture);
    await pumpEventQueue();
    expect(model.count, 9);
  });

  test('a sharing change asks for one more read and keeps the count', () async {
    final port = _Port();
    model.load(port, _target, _culture);
    await pumpEventQueue();
    final before = notified;
    port
      ..total = 4
      ..refreshes.add(null);
    await pumpEventQueue();
    expect(notified, before + 1);
    expect(model.count, 3);
    model.load(port, _target, _culture);
    await pumpEventQueue();
    expect(port.reads, 2);
    expect(model.count, 4);
  });

  test('a new target never shows the old count', () async {
    final port = _Port();
    model.load(port, _target, _culture);
    await pumpEventQueue();
    port.gate = Completer<void>();
    model.load(port, 'b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0', _culture);
    expect(model.count, isNull);
    expect(model.reading, isTrue);
    port.gate!.complete();
    await pumpEventQueue();
    expect(model.count, 3);
  });

  test('a read that ends after closing does nothing', () async {
    final local = OfficialFleetShipCount(now: () => now);
    final port = _Port()..gate = Completer<void>();
    local.load(port, _target, _culture);
    local.dispose();
    port.gate!.complete();
    await pumpEventQueue();
    expect(port.reads, 1);
  });
}
