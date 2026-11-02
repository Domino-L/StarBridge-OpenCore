import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

class _Harness {
  _Harness({bool supported = true}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 0,
    );
    if (supported) session.acceptHostCapabilities(['account.restoreDisplay']);
    subscription = pair.host.incoming.listen(requests.add);
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  int sequence = 0;
  BridgeRequestOperation read(
    List<BridgeEnvelope?> frames, {
    Duration? timeout,
  }) => session.beginRequest(
    'account.getCurrent',
    payload: {'schemaVersion': 1},
    timeout: timeout,
    onAccountRestoreDisplay: frames.add,
  );
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<void> progress(String root, {int generation = 0}) async {
    await pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.restoreDisplay',
        sessionGeneration: generation,
        sequence: sequence++,
        payload: {
          'schemaVersion': 1,
          'rootCorrelationId': root,
          'retainedDisplay': {},
        },
      ),
    );
    await flush();
  }

  Future<void> finish(BridgeRequestOperation operation) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: 'account.getCurrent',
      correlationId: operation.correlationId,
      sessionGeneration: 0,
      status: 'ok',
      payload: {'schemaVersion': 1, 'state': 'signedOut'},
    ),
  );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  for (final boundary in ['cancel', 'generation', 'remoteError']) {
    test(
      '$boundary retires before a withdrawal callback starts another root',
      () async {
        final h = _Harness();
        addTearDown(h.close);
        BridgeRequestOperation? replacement;
        final first = h.session.beginRequest(
          'account.getCurrent',
          payload: {'schemaVersion': 1},
          onAccountRestoreDisplay: (frame) {
            if (frame == null) {
              replacement = h.session.beginRequest(
                'account.getCurrent',
                payload: {'schemaVersion': 1},
              );
            }
          },
        );
        final done = first.future.then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
        await h.progress(first.correlationId!);
        if (boundary == 'cancel') {
          await first.cancel();
        } else if (boundary == 'generation') {
          h.session.advanceGeneration(1);
        } else {
          await h.pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: 'account.getCurrent',
              correlationId: first.correlationId,
              sessionGeneration: 0,
              status: 'error',
              payload: const {},
              error: const BridgeErrorBody(
                code: 'account.unavailable',
                message: 'Synthetic failure',
                retryable: true,
              ),
            ),
          );
        }
        expect(await done, isA<BridgeClientException>());
        final next = replacement!;
        expect(next.correlationId, isNot(first.correlationId));
        await h.pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: 'account.getCurrent',
            correlationId: next.correlationId,
            sessionGeneration: h.session.activeGeneration,
            status: 'ok',
            payload: const {'schemaVersion': 1, 'state': 'signedOut'},
          ),
        );
        expect(
          (await next.future).sessionGeneration,
          h.session.activeGeneration,
        );
      },
    );
  }

  test(
    'one progress observer cannot revive a consumer it synchronously cancelled',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      late BridgeRequestOperation second;
      final first = h.session.beginRequest(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
        onAccountRestoreDisplay: (frame) {
          if (frame != null) unawaited(second.cancel());
        },
      );
      final frames = <BridgeEnvelope?>[];
      second = h.read(frames);
      final cancelled = expectLater(
        second.future,
        throwsA(isA<BridgeCancelledException>()),
      );
      await h.progress(first.correlationId!);
      await cancelled;
      expect(frames, [null]);
      await h.finish(first);
      await first.future;
    },
  );

  test(
    'a root requested synchronously on display withdrawal is a new transport',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      BridgeRequestOperation? replacement;
      final first = h.session.beginRequest(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
        onAccountRestoreDisplay: (frame) {
          if (frame == null) {
            replacement = h.session.beginRequest(
              'account.getCurrent',
              payload: {'schemaVersion': 1},
            );
          }
        },
      );
      await h.progress(first.correlationId!);
      await h.finish(first);
      await first.future;
      final next = replacement!;
      try {
        expect(next.correlationId, isNot(first.correlationId));
        await h.flush();
        expect(
          h.requests.where((r) => r.name == 'account.getCurrent'),
          hasLength(2),
        );
      } finally {
        await h.finish(next);
        await next.future;
      }
    },
  );

  test('shared physical root replays only live progress and withdraws on completion', () async {
    final h = _Harness();
    addTearDown(h.close);
    final firstFrames = <BridgeEnvelope?>[], lateFrames = <BridgeEnvelope?>[];
    final first = h.read(firstFrames);
    await h.flush();
    expect(h.requests.single.payload['restoreDisplayProgress'], isTrue);
    await h.progress(first.correlationId!);
    expect(firstFrames.single, isNotNull);
    final late = h.read(lateFrames);
    expect(late.correlationId, first.correlationId);
    expect(lateFrames.single, same(firstFrames.single));
    await h.finish(first);
    await Future.wait([first.future, late.future]);
    expect(firstFrames.last, isNull);
    expect(lateFrames.last, isNull);
    final nextFrames = <BridgeEnvelope?>[];
    final next = h.read(nextFrames);
    await h.flush();
    expect(next.correlationId, isNot(first.correlationId));
    await h.progress(first.correlationId!);
    expect(nextFrames, isEmpty);
    await h.finish(next);
    await next.future;
    expect(
      h.requests.where((r) => r.name == 'account.getCurrent'),
      hasLength(2),
    );
  });

  for (final supported in [false, true]) {
    test(
      'unrequested root is not upgraded or split; capability=$supported',
      () async {
        final h = _Harness(supported: supported);
        addTearDown(h.close);
        final plain = h.session.beginRequest(
          'account.getCurrent',
          payload: {'schemaVersion': 1},
        );
        final frames = <BridgeEnvelope?>[];
        final observer = h.read(frames);
        await h.flush();
        expect(h.requests.single.payload, {'schemaVersion': 1});
        await h.progress(plain.correlationId!);
        expect(frames, isEmpty);
        await h.finish(plain);
        await Future.wait([plain.future, observer.future]);
      },
    );
  }

  test('one consumer cancellation withdraws its display without cancelling another', () async {
    final h = _Harness();
    addTearDown(h.close);
    final a = <BridgeEnvelope?>[], b = <BridgeEnvelope?>[];
    final first = h.read(a), second = h.read(b);
    final cancelled = expectLater(
      first.future,
      throwsA(isA<BridgeCancelledException>()),
    );
    await h.progress(first.correlationId!);
    await first.cancel();
    await cancelled;
    expect(a.last, isNull);
    expect(b.last, isNotNull);
    await h.flush();
    expect(h.requests.where((r) => r.name == 'bridge.cancel'), isEmpty);
    await h.finish(second);
    await second.future;
    expect(b.last, isNull);
  });

  test('independent deadline withdraws only the expired observer', () async {
    final h = _Harness();
    addTearDown(h.close);
    final a = <BridgeEnvelope?>[], b = <BridgeEnvelope?>[];
    final first = h.read(a, timeout: const Duration(milliseconds: 30));
    final second = h.read(b);
    final expired = expectLater(
      first.future,
      throwsA(isA<BridgeTimeoutException>()),
    );
    await h.progress(first.correlationId!);
    await expired;
    expect(a.last, isNull);
    expect(b.last, isNotNull);
    await h.finish(second);
    await second.future;
  });

  for (final boundary in [
    'generation',
    'disconnect',
    'accountWrite',
    'bootstrap',
    'mode',
    'capability',
  ]) {
    test(
      '$boundary withdraws active display and rejects late progress',
      () async {
        final h = _Harness();
        addTearDown(h.close);
        final frames = <BridgeEnvelope?>[];
        final read = h.read(frames);
        final result = read.future.then<void>((_) {}, onError: (Object _) {});
        await h.progress(read.correlationId!);
        expect(frames.last, isNotNull);
        if (boundary == 'generation') {
          h.session.advanceGeneration(1);
        } else if (boundary == 'disconnect') {
          await h.session.close();
        } else if (boundary == 'mode') {
          await h.session.runConnectionModeChange(() async {});
        } else if (boundary == 'capability') {
          h.session.acceptHostCapabilities(const []);
        } else if (boundary == 'bootstrap') {
          await h.pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'event',
              name: 'bootstrap.invalidated',
              sessionGeneration: 0,
              sequence: h.sequence++,
              payload: const {},
            ),
          );
        } else {
          final write = h.session.beginRequest(
            'account.login',
            payload: {'schemaVersion': 1},
          );
          final ignored = write.future.then<void>(
            (_) {},
            onError: (Object _) {},
          );
          await write.cancel();
          await ignored;
        }
        await h.flush();
        expect(frames.last, isNull);
        final count = frames.length;
        if (boundary != 'disconnect') await h.progress(read.correlationId!);
        expect(frames, hasLength(count));
        await read.cancel();
        await result;
      },
    );
  }
}
