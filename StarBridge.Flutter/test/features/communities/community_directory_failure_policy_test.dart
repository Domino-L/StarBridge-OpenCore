import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'community_shortcuts_test.dart' show QueuedPort;

final class FailurePolicyPort extends QueuedPort {
  String? failure;
  Completer<CommunityDirectory>? pending;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    if (pending != null) return pending!.future;
    if (failure != null) throw CommunityFailure(failure!);
    return CommunityDirectory(view, query, rows);
  }
}

void main() {
  test('unfiltered mine failures update the shared shortcuts without overriding a newer joined read', () async {
    final port = FailurePolicyPort();
    final model = CommunitiesModule(port);
    try {
      await model.refresh(newView: 'mine');
      port.failure = 'readTransient';
      await model.refresh();
      expect(model.joinedLoaded, isTrue);
      expect(model.joined.every((row) => row.displayOnly), isTrue);
      expect(model.joinedError, 'readTransient');
      port.failure = null;
      await model.refresh();
      expect(model.joinedError, isNull);
      final older = port.pending = Completer<CommunityDirectory>();
      final directoryRead = model.refresh();
      final newer = port.pending = Completer<CommunityDirectory>();
      final joinedRead = model.refreshJoined();
      newer.complete(
        CommunityDirectory('mine', '', [
          CommunityCard(
            targetRef: 'c' * 32,
            organizationRef: 'newest',
            name: 'Newest directory',
            relationship: 'member',
          ),
        ]),
      );
      await joinedRead;
      older.completeError(const CommunityFailure('readTransient'));
      await directoryRead;
      expect(model.joined.single.name, 'Newest directory');
      expect(model.joined.single.displayOnly, isFalse);
      expect(model.joinedError, isNull);
    } finally {
      model.dispose();
    }
  });
  test('joined refresh keeps content while pending and known transient failure retains only original readonly display', () async {
    final port = FailurePolicyPort();
    var now = DateTime.utc(2026, 10, 15, 10);
    final model = CommunitiesModule(port, now: () => now);
    try {
      await model.refreshJoined();
      final previous = model.joined, old = previous.first;
      expect(model.canExecute(old), isTrue);
      port.pending = Completer();
      final reading = model.refreshJoined();
      expect(model.joined, same(previous));
      expect(model.joinedBusy, isTrue);
      now = now.add(const Duration(minutes: 5));
      port.pending!.completeError(const CommunityFailure('readTransient'));
      await reading;
      expect(model.joined.map((r) => r.name), previous.map((r) => r.name));
      expect(model.joinedLoaded, isTrue);
      expect(model.joinedError, 'readTransient');
      expect(model.joinedCachedAtUtc, DateTime.utc(2026, 10, 15, 10));
      expect(model.canExecute(old), isFalse);
      expect(
        model.joined.every(
          (r) =>
              r.displayOnly &&
              r.targetRef.isEmpty &&
              r.actions.isEmpty &&
              r.relationship == 'none' &&
              r.memberCount == null,
        ),
        isTrue,
      );
      await model.openJoined(model.joined.first);
      await model.execute(model.joined.first, 'leave');
      expect(model.selected, isNull);
      expect(port.writes, isEmpty);
      port.pending = null;
      await model.refreshJoined();
      expect(model.joinedError, isNull);
      expect(model.joinedCachedAtUtc, isNull);
      expect(model.canExecute(model.joined.first), isTrue);
    } finally {
      model.dispose();
    }
  });
  for (final code in [
    'unavailable',
    'notAllowed',
    'dataInvalid',
    'identityUnavailable',
  ]) {
    test(
      'joined $code failure does not inherit a generic retryable retention policy',
      () async {
        final port = FailurePolicyPort();
        final model = CommunitiesModule(port);
        try {
          await model.refreshJoined();
          port.failure = code;
          await model.refreshJoined();
          expect(model.joined, isEmpty);
          expect(model.joinedLoaded, isFalse);
          expect(model.joinedCachedAtUtc, isNull);
          expect(model.joinedError, code);
        } finally {
          model.dispose();
        }
      },
    );
  }
  test('manual directory refresh keeps the picture and transient failure preserves its original time without action grants', () async {
    final port = FailurePolicyPort();
    var now = DateTime.utc(2026, 10, 15, 10);
    final model = CommunitiesModule(port, now: () => now);
    try {
      await model.refresh(newView: 'discover');
      final previous = model.directory!, old = previous.items.first;
      port.pending = Completer();
      final reading = model.refresh();
      expect(model.directory, same(previous));
      now = now.add(const Duration(minutes: 5));
      port.pending!.completeError(const CommunityFailure('readTransient'));
      await reading;
      expect(
        model.directory!.items.map((r) => r.name),
        previous.items.map((r) => r.name),
      );
      expect(model.directory!.cachedAtUtc, DateTime.utc(2026, 10, 15, 10));
      expect(model.directory!.items.every((r) => r.displayOnly), isTrue);
      expect(model.canExecute(old), isFalse);
      port.pending = null;
      port.failure = 'unavailable';
      await model.refresh(silent: true);
      expect(model.directory, isNull);
    } finally {
      model.dispose();
    }
  });
  test(
    'account invalidation cannot be repaired by an old transient failure',
    () async {
      final port = FailurePolicyPort();
      final model = CommunitiesModule(port);
      try {
        await model.refreshJoined();
        port.pending = Completer();
        final reading = model.refreshJoined();
        port.changes.add(null);
        port.pending!.completeError(const CommunityFailure('readTransient'));
        await reading;
        expect(model.joined, isEmpty);
        expect(model.joinedCachedAtUtc, isNull);
      } finally {
        model.dispose();
      }
    },
  );
  const path = String.fromEnvironment('STARBRIDGE_COMMUNITY_FAILURE_WIRE');
  for (final label in [
    'outage',
    'rateLimited',
    'forbidden',
    'unknown',
    'invalid',
  ]) {
    test(
      'actual Native directory $label is classified by the real adapter and model',
      () async {
        final h = NativeDirectoryFailureHost(
          jsonDecode(File(path).readAsStringSync()) as Map,
        );
        final model = CommunitiesModule(h.port);
        try {
          await model.refreshJoined();
          expect(model.joined.single.name, 'Directory before failure');
          h.label = label;
          await model.refreshJoined();
          if (label == 'outage' || label == 'rateLimited') {
            expect(model.joined.single.name, 'Directory before failure');
            expect(model.joined.single.displayOnly, isTrue);
            expect(model.joinedError, 'readTransient');
          } else {
            expect(model.joined, isEmpty);
            expect(
              model.joinedError,
              {
                'forbidden': 'notAllowed',
                'unknown': 'unavailable',
                'invalid': 'dataInvalid',
              }[label],
            );
          }
          expect(
            h.requests.where((r) => r.name == 'account.getCurrent').length,
            2,
          );
          h.label = 'recovered';
          await model.refreshJoined();
          expect(model.joined.single.displayOnly, isFalse);
          expect(model.canExecute(model.joined.single), isTrue);
        } finally {
          model.dispose();
          await h.close();
        }
      },
      skip: path.isEmpty
          ? 'Requires actual Native directory failure wire'
          : false,
    );
  }
}

final class NativeDirectoryFailureHost {
  NativeDirectoryFailureHost(this.fixtures) {
    final root = envelope('root');
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: root.sessionGeneration,
    );
    session.acceptHostCapabilities(['communities.read']);
    port = BridgeCommunities(session);
    incoming = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'bridge.cancel') return;
      final sample = envelope(
        request.name == 'account.getCurrent' ? 'root' : label,
      );
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: sample.accountContext,
            status: sample.status,
            payload: sample.payload,
            error: sample.error,
          ),
        ),
      );
    });
  }
  final Map fixtures;
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeCommunities port;
  late final StreamSubscription<BridgeEnvelope> incoming;
  String label = 'live';
  final requests = <BridgeEnvelope>[];
  BridgeEnvelope envelope(String label) =>
      BridgeEnvelope.fromJson((fixtures[label] as Map).cast<String, Object?>());
  Future<void> close() async {
    await port.close();
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}
