import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_retained_display.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _prefix = String.fromEnvironment('STARBRIDGE_FRIENDS_PAGING_WIRE_PREFIX');
const _skip = _prefix == '' ? 'Requires actual Native paging capture' : false;
const _deadline = Duration(seconds: 5);
Map<String, Object?> _wire(String kind) =>
    (jsonDecode(File('$_prefix-$kind.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
BridgeEnvelope _frame(Object? value) =>
    BridgeEnvelope.fromJson((value as Map).cast<String, Object?>());

void main() {
  test('actual Native large fresh pages reach the adapter without extra root reads', () async {
    final host = _FreshWire(_wire('fresh'));
    addTearDown(host.close);
    var complete = false;
    final pending = host.adapter.read()..then((_) => complete = true);
    await host.lastArrived.future.timeout(_deadline);
    expect(complete, isFalse);
    await host.finishLast();
    final result = await pending.timeout(_deadline);
    expect(result.state, FriendsReadState.ready);
    expect(result.snapshot!.groups[FriendsSection.incoming], hasLength(1400));
    expect(
      host.requests.where((r) => r.name == 'account.getCurrent'),
      hasLength(1),
    );
    expect(host.requests.where((r) => r.name == 'friends.read'), hasLength(1));
    expect(
      host.requests
          .firstWhere((r) => r.name == 'friends.read')
          .payload['pagedResponse'],
      isTrue,
    );
    expect(
      host.requests.where((r) => r.name == 'friends.readPage').length,
      greaterThan(1),
    );
  }, skip: _skip);
  test(
    'actual Native large online cache is complete before original HTTP result',
    () async {
      final host = _FreshWire(_wire('online'), online: true);
      addTearDown(host.close);
      var complete = false;
      final pending = host.adapter.read()..then((_) => complete = true);
      final cache = await host.cached.future.timeout(_deadline);
      expect(complete, isFalse);
      expect(cache.snapshot.groups[FriendsSection.incoming], hasLength(1400));
      expect(
        cache.snapshot.groups.values
            .expand((rows) => rows)
            .every((row) => row.targetRef == null && row.actions.isEmpty),
        isTrue,
      );
      await host.releaseFresh();
      expect((await pending.timeout(_deadline)).state, FriendsReadState.ready);
      expect(
        host.requests.where((r) => r.name == 'account.getCurrent'),
        hasLength(1),
      );
    },
    skip: _skip,
  );
  for (final rootWins in [false, true]) {
    test(
      'actual Native retained paging handles root completion first=$rootWins',
      () async {
        final host = _RetainedWire(_wire('retained'));
        addTearDown(host.close);
        await host.start();
        await host.lastArrived.future.timeout(_deadline);
        expect(host.displays, isEmpty);
        if (rootWins) {
          await host.completeRoot();
          await host.finishLast();
          await Future<void>.delayed(Duration.zero);
          expect(host.displays, isEmpty);
          expect(host.display.value, isNull);
        } else {
          await host.finishLast();
          final cache = await host.cached.future.timeout(_deadline);
          expect(
            cache.snapshot.groups[FriendsSection.incoming],
            hasLength(1400),
          );
          await host.completeRoot();
          expect(host.display.value, isNotNull);
        }
        final children = host.requests.where(
          (r) => r.name == 'account.offlineData.read',
        );
        final readId =
            (_frame(host.wire['prepared']).payload['retainedDisplay']
                as Map)['readId'];
        expect(
          children.every(
            (r) =>
                r.accountContext == null &&
                r.payload['readId'] == readId &&
                r.payload['pagedResponse'] == true,
          ),
          isTrue,
        );
        expect(
          host.requests.where((r) => r.name == 'account.getCurrent'),
          hasLength(1),
        );
      },
      skip: _skip,
    );
  }
}

final class _FreshWire {
  _FreshWire(this.wire, {this.online = false}) {
    final root = _frame(wire['root']);
    fresh = ((wire[online ? 'freshFrames' : 'frames']) as List)
        .map(_frame)
        .toList();
    cachedFrames = online
        ? (wire['cachedFrames'] as List).map(_frame).toList()
        : [];
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: root.sessionGeneration,
    );
    session.acceptHostCapabilities([
      'friends.read',
      'friends.readPages',
      if (online) 'friends.readDisplay',
    ]);
    adapter = BridgeFriendsAdapter(session);
    cacheSubscription = adapter.cachedDisplays.listen((value) {
      if (value != null && !cached.isCompleted) cached.complete(value);
    });
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        unawaited(reply(request, root));
      } else if (request.name == 'friends.read') {
        original = request;
        if (online) {
          final prepared = _frame(wire['prepared']);
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: prepared.name,
                sessionGeneration: request.sessionGeneration,
                sequence: prepared.sequence,
                payload: {
                  ...prepared.payload,
                  'requestCorrelationId': request.correlationId,
                },
              ),
            ),
          );
        } else {
          _freshReply(request, fresh.first);
        }
      } else if (request.name == 'friends.readPage') {
        final frames = request.payload.containsKey('displayRequestId')
            ? cachedFrames
            : fresh;
        final source = frames.singleWhere(
          (f) =>
              (f.payload['page'] as Map)['offset'] == request.payload['offset'],
        );
        if (request.payload.containsKey('displayRequestId')) {
          unawaited(reply(request, source));
        } else {
          _freshReply(request, source);
        }
      }
    });
  }
  final Map<String, Object?> wire;
  final bool online;
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeFriendsAdapter adapter;
  late final List<BridgeEnvelope> fresh, cachedFrames;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final StreamSubscription<FriendsCachedDisplay?> cacheSubscription;
  final requests = <BridgeEnvelope>[];
  final lastArrived = Completer<void>();
  final cached = Completer<FriendsCachedDisplay>();
  BridgeEnvelope? original, held, heldSource;
  Future<void> reply(BridgeEnvelope request, BridgeEnvelope source) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: source.protocolVersion,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: source.accountContext,
          status: source.status,
          error: source.error,
          payload: source.payload,
        ),
      );
  void _freshReply(BridgeEnvelope request, BridgeEnvelope source) {
    if (!online && (source.payload['page'] as Map)['nextOffset'] == null) {
      held = request;
      heldSource = source;
      if (!lastArrived.isCompleted) lastArrived.complete();
    } else {
      unawaited(reply(request, source));
    }
  }

  Future<void> finishLast() => reply(held!, heldSource!);
  Future<void> releaseFresh() => reply(original!, fresh.first);
  Future<void> close() async {
    await adapter.close();
    await cacheSubscription.cancel();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

final class _RetainedWire {
  _RetainedWire(this.wire) {
    frames = (wire['frames'] as List).map(_frame).toList();
    final prepared = _frame(wire['prepared']);
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: prepared.sessionGeneration,
    );
    session.acceptHostCapabilities([
      'account.restoreDisplay',
      'account.offlineData.read',
      'friends.readPages',
    ]);
    display = FriendsRetainedDisplay(session, () => true, (value) {
      if (value == null) return;
      displays.add(value);
      if (!cached.isCompleted) cached.complete(value);
    });
    events = session.events.listen(display.observeEvent);
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        root = request;
        if (!rootArrived.isCompleted) rootArrived.complete();
      } else if (request.name == 'account.offlineData.read') {
        final offset = request.payload['offset'] ?? 0;
        final source = frames.singleWhere(
          (f) =>
              ((f.payload['directory'] as Map)['page'] as Map)['offset'] ==
              offset,
        );
        if (identical(source, frames.last)) {
          held = request;
          heldSource = source;
          if (!lastArrived.isCompleted) lastArrived.complete();
        } else {
          unawaited(reply(request, source));
        }
      }
    });
  }
  final Map<String, Object?> wire;
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final FriendsRetainedDisplay display;
  late final List<BridgeEnvelope> frames;
  late final StreamSubscription<BridgeEnvelope> subscription, events;
  late Future<BridgeEnvelope> reading;
  final requests = <BridgeEnvelope>[];
  final displays = <FriendsCachedDisplay>[];
  final rootArrived = Completer<void>(), lastArrived = Completer<void>();
  final cached = Completer<FriendsCachedDisplay>();
  BridgeEnvelope? root, held, heldSource;
  Future<void> reply(BridgeEnvelope request, BridgeEnvelope source) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: source.protocolVersion,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: source.accountContext,
          status: source.status,
          error: source.error,
          payload: source.payload,
        ),
      );
  Future<void> start() async {
    reading = display.read();
    unawaited(
      reading.then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
    );
    await rootArrived.future.timeout(_deadline);
    final prepared = _frame(wire['prepared']);
    await pair.host.send(
      BridgeEnvelope(
        protocolVersion: prepared.protocolVersion,
        messageType: 'event',
        name: prepared.name,
        sessionGeneration: prepared.sessionGeneration,
        sequence: prepared.sequence,
        payload: {
          ...prepared.payload,
          'rootCorrelationId': root!.correlationId,
        },
      ),
    );
  }

  Future<void> finishLast() => reply(held!, heldSource!);
  Future<void> completeRoot() async {
    await reply(root!, _frame(wire['completed']));
    for (final event in wire['events'] as List) {
      await pair.host.send(_frame(event));
    }
    await reading.timeout(_deadline);
  }

  Future<void> close() async {
    display.dispose();
    await subscription.cancel();
    await events.cancel();
    await session.close();
    await pair.host.close();
  }
}
