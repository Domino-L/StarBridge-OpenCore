import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_directory_logo_test.dart' as fixture;

class _MediaFailureBridge extends CommunityHarness {
  _MediaFailureBridge({required super.holdNames, required super.responses})
    : super(
        legacy: true,
        capabilities: ['communities.read', 'communities.media'],
      );
  @override
  Future<void> reply(BridgeEnvelope request) =>
      request.name != 'communities.media'
      ? super.reply(request)
      : connection.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: request.accountContext,
            status: 'error',
            error: const BridgeErrorBody(
              code: 'communities.unavailable',
              message: 'Synthetic image failure',
              retryable: true,
            ),
            payload: const {},
          ),
        );
}

class _Reads {
  _Reads({
    bool holdDirectory = false,
    String view = 'discover',
    bool failMedia = false,
  }) {
    final held = {'communities.media', if (holdDirectory) 'communities.read'};
    final responses = {
      'communities.read': {...fixture.directory, 'view': view},
      'communities.media': fixture.media,
    };
    bridge = scoped(
      () => failMedia
          ? _MediaFailureBridge(holdNames: held, responses: responses)
          : CommunityHarness(
              legacy: true,
              capabilities: ['communities.read', 'communities.media'],
              holdNames: held,
              responses: responses,
            ),
    );
    module = scoped(() => CommunitiesModule(bridge.adapter));
    metrics.route('/communities');
  }
  int tick = 0;
  final rows = <Map<String, Object>>[];
  late final metrics = LoadingMetrics(nowUs: () => tick++, write: rows.add);
  late final CommunityHarness bridge;
  late final CommunitiesModule module;
  final replied = <BridgeEnvelope>{};
  T scoped<T>(T Function() work) =>
      runZoned(work, zoneValues: {loadingMetricsZoneKey: metrics});
  Future<void> until(bool Function() ready) async {
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (!ready() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(
      ready(),
      isTrue,
      reason: 'Controlled bridge fixture did not settle.',
    );
  }

  Future<void> mediaStarted() => until(
    () =>
        bridge.requests.where((r) => r.name == 'communities.media').length >= 3,
  );
  Future<void> releaseMedia() async {
    bridge.holdNames.remove('communities.media');
    for (final request
        in bridge.requests
            .where((r) => r.name == 'communities.media' && !replied.contains(r))
            .toList()) {
      replied.add(request);
      await bridge.reply(request);
    }
    await Future<void>.delayed(Duration.zero);
  }

  bool get imagesReady =>
      module.directory?.items.every((r) => r.logo != null) == true;
  Future<void> close() async {
    await releaseMedia();
    module.dispose();
    await Future<void>.delayed(Duration.zero);
    await bridge.close();
    metrics.stop();
  }
}

void main() {
  test(
    'legacy full read retains foreground waiting and complete image semantics',
    () async {
      final f = _Reads();
      addTearDown(f.close);
      var complete = false;
      final reading = f
          .scoped(
            () => f.metrics.foreground(
              () => f.bridge.adapter.read(view: 'discover', query: ''),
            ),
          )
          .then((page) {
            complete = true;
            return page;
          });
      await f.mediaStarted();
      expect(complete, isFalse);
      expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
      await f.releaseMedia();
      final page = await reading;
      expect(page.items.every((row) => row.logo != null), isTrue);
      expect(f.metrics.pendingTransportsFor(1), 0);
    },
  );

  test(
    'failed optional logos retain text and real physical error counts',
    () async {
      final f = _Reads(failMedia: true);
      addTearDown(f.close);
      await f.scoped(() => f.module.refresh(newView: 'discover'));
      await f.mediaStarted();
      await f.releaseMedia();
      await f.until(() => f.metrics.pendingTransportsFor(1) == 0);
      expect(f.module.directory!.items, hasLength(17));
      expect(f.module.busy, isFalse);
      expect(f.module.directory!.items.every((r) => r.logo == null), isTrue);
      expect(
        f.rows.where(
          (r) =>
              r['kind'] == 'transport' &&
              r['operation'] == 'communities.media' &&
              r['outcome'] == 'error',
        ),
        hasLength(17),
      );
    },
  );

  test(
    'same-reference refresh keeps existing logos while revalidating',
    () async {
      final f = _Reads();
      addTearDown(f.close);
      await f.scoped(() => f.module.refresh(newView: 'discover'));
      await f.mediaStarted();
      await f.releaseMedia();
      await f.until(() => f.imagesReady);
      final before = f.module.directory!.items.map((r) => r.logo).toList();
      f.bridge.holdNames.add('communities.media');
      final count = f.bridge.requests
          .where((r) => r.name == 'communities.media')
          .length;
      await f.scoped(() => f.module.refresh());
      await f.until(
        () =>
            f.bridge.requests
                .where((r) => r.name == 'communities.media')
                .length ==
            count + 3,
      );
      expect(f.module.busy, isFalse);
      expect(f.module.directory!.items.map((r) => r.logo), before);
      await f.releaseMedia();
      await f.until(() => f.metrics.pendingTransportsFor(1) == 0);
    },
  );

  test('directory text becomes usable before optional logos finish', () async {
    final bridge = CommunityHarness(
      legacy: true,
      capabilities: ['communities.read', 'communities.media'],
      holdNames: {'communities.media'},
      responses: {
        'communities.read': fixture.directory,
        'communities.media': fixture.media,
      },
    );
    final module = CommunitiesModule(bridge.adapter);
    final reading = module.refresh(newView: 'discover');
    try {
      await bridge.readArrived.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(
        bridge.requests.where((r) => r.name == 'communities.read'),
        hasLength(1),
      );
      expect(
        bridge.requests.where((r) => r.name == 'communities.media'),
        hasLength(3),
      );
      // This is the actual page model consumed by CommunitiesPage, after
      // successful metadata and before any optional media response arrives.
      expect(module.directory?.items, hasLength(17));
      expect(module.busy, isFalse);
      expect(module.error, isNull);
    } finally {
      // Resume automatic replies for all later workers before releasing the
      // currently held requests. A temporary empty queue is not batch completion.
      bridge.holdNames.remove('communities.media');
      final pending = bridge.requests
          .where((r) => r.name == 'communities.media')
          .toList();
      for (final request in pending) {
        await bridge.reply(request);
      }
      await reading.timeout(const Duration(seconds: 2));
      module.dispose();
      await Future<void>.delayed(Duration.zero);
      await bridge.close();
    }
  });

  test(
    'one metadata read publishes all later logos without losing row metadata',
    () async {
      final f = _Reads();
      addTearDown(f.close);
      final reading = f.scoped(() => f.module.refresh(newView: 'discover'));
      await f.mediaStarted();
      await reading;
      expect(f.module.directory!.items, hasLength(17));
      expect(f.module.busy, isFalse);
      expect(f.metrics.pendingPageReadsFor(1), 0);
      expect(f.metrics.pendingTransportsFor(1), 3);
      expect(
        f.rows
            .where(
              (r) =>
                  r['kind'] == 'transportStart' &&
                  r['operation'] == 'communities.media',
            )
            .every((r) => r['activity'] == 'background'),
        isTrue,
      );
      final before = f.module.directory!.items.first;
      await f.releaseMedia();
      await f.until(() => f.imagesReady);
      final after = f.module.directory!.items.first;
      expect(
        (after.name, after.targetRef, after.actions, after.relationship),
        (before.name, before.targetRef, before.actions, before.relationship),
      );
      expect(
        f.bridge.requests.where((r) => r.name == 'communities.read'),
        hasLength(1),
      );
      expect(
        f.bridge.requests.where((r) => r.name == 'communities.media'),
        hasLength(17),
      );
    },
  );

  test(
    'real foreground metadata still waits while optional media is passive',
    () async {
      final f = _Reads(holdDirectory: true);
      addTearDown(f.close);
      final reading = f.scoped(
        () => f.metrics.foreground(() => f.module.refresh(newView: 'discover')),
      );
      await f.until(
        () => f.bridge.requests.any((r) => r.name == 'communities.read'),
      );
      expect(f.module.directory, isNull);
      expect(f.module.busy, isTrue);
      expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
      f.bridge.holdNames.remove('communities.read');
      await f.bridge.reply(
        f.bridge.requests.singleWhere((r) => r.name == 'communities.read'),
      );
      await f.mediaStarted();
      await reading;
      expect(f.metrics.pendingPageReadsFor(1), 0);
      expect(f.metrics.pendingTransportsFor(1), 3);
    },
  );

  test(
    'account boundary rejects old image publication and queued work',
    () async {
      final f = _Reads();
      addTearDown(f.close);
      await f.scoped(() => f.module.refresh(newView: 'discover'));
      await f.mediaStarted();
      await f.bridge.connection.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 5,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await f.until(() => f.module.directory == null);
      await f.releaseMedia();
      await Future<void>.delayed(Duration.zero);
      expect(f.module.directory, isNull);
      expect(
        f.bridge.requests.where((r) => r.name == 'communities.media'),
        hasLength(3),
      );
    },
  );

  test('image maintenance preserves text and rejects old bytes before a fresh read', () async {
    final f = _Reads();
    addTearDown(f.close);
    await f.scoped(() => f.module.refresh(newView: 'discover'));
    await f.mediaStarted();
    f.module.beginImageMaintenance();
    f.module.endImageMaintenance();
    await f.releaseMedia();
    await f.until(() => f.metrics.pendingTransportsFor(1) == 0);
    expect(f.module.directory!.items, hasLength(17));
    expect(f.module.directory!.items.every((r) => r.logo == null), isTrue);
    expect(
      f.bridge.requests.where((r) => r.name == 'communities.media'),
      hasLength(3),
    );
    await f.scoped(() => f.module.refresh());
    await f.until(() => f.imagesReady);
    expect(
      f.bridge.requests.where((r) => r.name == 'communities.read'),
      hasLength(2),
    );
  });

  test(
    'new query retires queued images without releasing active physical reads',
    () async {
      final f = _Reads();
      addTearDown(f.close);
      await f.scoped(() => f.module.refresh(newView: 'discover'));
      await f.mediaStarted();
      f.bridge.responses['communities.read'] = {
        ...fixture.directory,
        'query': 'new',
        'items': (fixture.directory['items'] as List)
            .map(
              (row) => {
                ...Map<String, Object?>.from(row as Map),
                'name': 'Replacement',
                'logoDeferred': false,
              },
            )
            .toList(),
      };
      await f.scoped(() => f.module.refresh(newQuery: 'new'));
      expect(
        f.module.directory!.items.every((r) => r.name == 'Replacement'),
        isTrue,
      );
      expect(f.metrics.pendingTransportsFor(1), 3);
      await f.releaseMedia();
      await f.until(() => f.metrics.pendingTransportsFor(1) == 0);
      expect(f.module.directory!.query, 'new');
      expect(f.module.directory!.items.every((r) => r.logo == null), isTrue);
      expect(
        f.bridge.requests.where((r) => r.name == 'communities.media'),
        hasLength(3),
      );
    },
  );

  test('joined metadata also finishes before its optional logos', () async {
    final f = _Reads(view: 'mine');
    addTearDown(f.close);
    await f.scoped(f.module.refreshJoined);
    await f.mediaStarted();
    expect(f.module.joined, hasLength(17));
    expect(f.module.joinedBusy, isFalse);
    await f.releaseMedia();
    await f.until(() => f.module.joined.every((r) => r.logo != null));
    expect(
      f.bridge.requests.where((r) => r.name == 'communities.read'),
      hasLength(1),
    );
  });
}
