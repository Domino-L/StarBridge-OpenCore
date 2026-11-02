import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _prefix = String.fromEnvironment(
  'STARBRIDGE_FRIEND_COMMAND_PAGING_WIRE_PREFIX',
);
const _skip = _prefix == ''
    ? 'Requires actual Native command paging wire'
    : false;
const _timeout = Duration(seconds: 5);
Map<String, Object?> _load(String suffix) =>
    (jsonDecode(File('$_prefix-$suffix.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
BridgeEnvelope _frame(Object? raw) =>
    BridgeEnvelope.fromJson((raw as Map).cast<String, Object?>());

void main() {
  test('actual accepted command collects every result row without replay or another read', () async {
    final host = _CommandWire();
    addTearDown(host.close);
    await host.enter();
    final at = host.module.lastSuccessfulReadUtc;
    host.now = host.now.add(const Duration(hours: 1));
    await host.module
        .execute(host.module.rows.first, 'reject')
        .timeout(_timeout);
    expect(host.module.feedbackSuccess, isTrue);
    expect(host.module.rows, hasLength(1399));
    expect(host.module.lastSuccessfulReadUtc, isNot(at));
    expect(
      host.requests.where((r) => r.name == 'friends.execute'),
      hasLength(1),
    );
    expect(
      host.requests
          .firstWhere((r) => r.name == 'friends.execute')
          .payload['pagedResponse'],
      isTrue,
    );
    expect(host.requests.where((r) => r.name == 'friends.read'), hasLength(1));
    expect(
      host.requests.where((r) => r.name == 'account.getCurrent'),
      hasLength(2),
    );
  }, skip: _skip);
  for (final mode in ['pageError', 'pageTimeout', 'malformed', 'legacyLarge']) {
    test(
      '$mode preserves confirmed success, readonly rows, time and viewport',
      () async {
        final host = _CommandWire(
          mode: mode,
          commandPages: mode != 'legacyLarge',
        );
        addTearDown(host.close);
        await host.enter();
        final at = host.module.lastSuccessfulReadUtc;
        final view = host.module.viewEpoch;
        host.module.rememberScroll(173, expectedEpoch: view);
        host.now = host.now.add(const Duration(hours: 1));
        await host.module
            .execute(host.module.rows.first, 'reject')
            .timeout(_timeout);
        expect(host.module.feedbackSuccess, isTrue);
        expect(host.module.feedback, 'success.reject');
        expect(host.module.refreshFailed, isTrue);
        expect(host.module.rows, hasLength(1400));
        expect(host.module.lastSuccessfulReadUtc, at);
        expect(host.module.scrollOffset, 173);
        expect(host.module.viewEpoch, view);
        expect(host.module.incomingAttention.value, 0);
        for (final row in host.module.rows) {
          expect(row.actions, isEmpty);
          expect(row.targetRef, isNull);
          expect(row.chatTargetRef, isNull);
          expect(row.conversationKey, isNull);
        }
        await host.module.execute(host.module.rows.first, 'reject');
        expect(
          host.requests.where((r) => r.name == 'friends.execute'),
          hasLength(1),
        );
        expect(
          host.requests.where((r) => r.name == 'friends.read'),
          hasLength(1),
        );
        expect(
          host.requests.where((r) => r.name == 'account.getCurrent'),
          hasLength(2),
        );
      },
      skip: _skip,
    );
  }
  test('small legacy accepted response remains a complete directory', () async {
    final host = _CommandWire(mode: 'small', commandPages: false);
    addTearDown(host.close);
    await host.enter();
    await host.module.execute(host.module.rows.first, 'reject');
    expect(host.module.feedbackSuccess, isTrue);
    expect(host.module.rows, hasLength(1));
    expect(host.module.refreshFailed, isFalse);
    expect(
      host.requests
          .firstWhere((r) => r.name == 'friends.execute')
          .payload
          .containsKey('pagedResponse'),
      isFalse,
    );
  }, skip: _skip);
  test(
    'foreign owner cannot confirm an operation for the current module',
    () async {
      final host = _CommandWire(mode: 'foreign');
      addTearDown(host.close);
      await host.enter();
      await host.module.execute(host.module.rows.first, 'reject');
      expect(host.module.feedbackSuccess, isFalse);
      expect(host.module.snapshot, isNull);
      expect(
        host.requests.where((r) => r.name == 'friends.execute'),
        hasLength(1),
      );
    },
    skip: _skip,
  );
  test('a missing ACK remains unknown and never replays the POST', () async {
    final host = _CommandWire(mode: 'ackTimeout');
    addTearDown(host.close);
    await host.enter();
    await host.module
        .execute(host.module.rows.first, 'reject')
        .timeout(_timeout);
    expect(host.module.feedbackSuccess, isFalse);
    expect(host.module.feedback, 'outcomeUnknown');
    expect(host.module.snapshot, isNull);
    expect(
      host.requests.where((r) => r.name == 'friends.execute'),
      hasLength(1),
    );
  }, skip: _skip);
  for (final change in ['generation', 'mode', 'cancel']) {
    test('$change retires the exact result page without publishing stale rows', () async {
      final host = _CommandWire(mode: 'hold');
      addTearDown(host.close);
      await host.enter();
      final pending = host.module.execute(host.module.rows.first, 'reject');
      await host.commandArrived.future.timeout(_timeout);
      expect(
        host.requests
            .lastWhere((r) => r.name == 'friends.execute')
            .payload['pagedResponse'],
        isTrue,
      );
      await host.heldArrived.future.timeout(_timeout);
      expect(host.module.busy, isTrue);
      if (change == 'generation') {
        host.session.advanceGeneration(host.session.activeGeneration + 1);
      }
      if (change == 'mode') {
        await host.session.runConnectionModeChange(() async {});
      }
      if (change == 'cancel') host.adapter.cancelPending();
      await pending.timeout(_timeout);
      await host.releaseHeld();
      expect(host.module.snapshot, isNull);
      expect(
        host.requests.where((r) => r.name == 'friends.execute'),
        hasLength(1),
      );
      // Generation advancement clears pending requests before notifying owners;
      // it retires them locally without sending an old-generation cancellation.
      if (change != 'generation') {
        expect(
          host.requests
              .where((r) => r.name == 'bridge.cancel')
              .map((r) => r.payload['targetCorrelationId']),
          contains(host.held!.correlationId),
        );
      }
    }, skip: _skip);
  }
}

final class _CommandWire {
  _CommandWire({this.mode = 'complete', bool commandPages = true}) {
    wire = _load(mode == 'small' ? 'small-command' : 'command');
    legacy = _load('legacy-command');
    initial = (wire['initialFrames'] as List).map(_frame).toList();
    results = mode == 'small'
        ? []
        : (wire['frames'] as List).map(_frame).toList();
    final root = _frame(wire['root']);
    now = DateTime.parse(initial.first.payload['refreshedAt']! as String)
        .toUtc()
        .add(const Duration(seconds: 1));
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: root.sessionGeneration,
      requestTimeout: const Duration(milliseconds: 150),
    );
    session.acceptHostCapabilities([
      'friends.read',
      'friends.readPages',
      'friends.commands',
      if (commandPages) 'friends.commandPages',
    ]);
    adapter = BridgeFriendsAdapter(session);
    module = FriendsModule(adapter, now: () => now);
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        unawaited(reply(request, root));
      } else if (request.name == 'friends.read') {
        unawaited(reply(request, initial.first));
      } else if (request.name == 'friends.execute') {
        if (!commandArrived.isCompleted) commandArrived.complete();
        if (mode == 'ackTimeout') return;
        final paged = request.payload['pagedResponse'] == true;
        final source = _frame(
          mode == 'small' || paged ? wire['command'] : legacy['command'],
        );
        unawaited(
          reply(
            request,
            source,
            foreign: mode == 'foreign',
            malformed: mode == 'malformed' && paged,
          ),
        );
      } else if (request.name == 'friends.readPage') {
        final initialId = (initial.first.payload['page'] as Map)['snapshotId'];
        final isInitial = request.payload['snapshotId'] == initialId;
        final frames = isInitial ? initial : results.skip(1);
        final source = frames.singleWhere(
          (f) =>
              (f.payload['page'] as Map)['offset'] == request.payload['offset'],
        );
        final last = (source.payload['page'] as Map)['nextOffset'] == null;
        if (!isInitial && last && (mode == 'hold' || mode == 'pageTimeout')) {
          held = request;
          heldSource = source;
          if (!heldArrived.isCompleted) heldArrived.complete();
        } else {
          unawaited(
            reply(
              request,
              source,
              failure: !isInitial && last && mode == 'pageError',
            ),
          );
        }
      }
    });
  }
  final String mode;
  final pair = InMemoryBridgeConnection.createPair();
  late final Map<String, Object?> wire, legacy;
  late final List<BridgeEnvelope> initial, results;
  late final BridgeClientSession session;
  late final BridgeFriendsAdapter adapter;
  late final FriendsModule module;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late DateTime now;
  final requests = <BridgeEnvelope>[];
  final commandArrived = Completer<void>(), heldArrived = Completer<void>();
  BridgeEnvelope? held, heldSource;
  Future<void> enter() async {
    await module.enter().timeout(_timeout);
    module.select(FriendsSection.incoming);
    expect(module.rows, hasLength(mode == 'small' ? 2 : 1400));
  }

  Future<void> reply(
    BridgeEnvelope request,
    BridgeEnvelope source, {
    bool failure = false,
    bool foreign = false,
    bool malformed = false,
  }) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: source.protocolVersion,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: foreign
          ? const BridgeAccountContext(
              environment: 'other',
              authority: 'other',
              subject: 'other',
            )
          : source.accountContext,
      status: failure ? 'error' : source.status,
      error: failure
          ? const BridgeErrorBody(
              code: 'friends.snapshot_changed',
              message: 'Synthetic result retired',
              retryable: true,
            )
          : source.error,
      payload: malformed
          ? {
              ...source.payload,
              'directory': {'schemaVersion': 1},
            }
          : source.payload,
    ),
  );
  Future<void> releaseHeld() => reply(held!, heldSource!);
  Future<void> close() async {
    module.dispose();
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
