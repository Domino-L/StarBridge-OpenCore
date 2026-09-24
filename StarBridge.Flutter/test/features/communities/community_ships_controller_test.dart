import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort, mediaChunk;

final _target = 'a' * 32;
final _revision = 'b' * 64;

final class _Port implements CommunityShipsPort, CommunityShipsRefreshPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final publications = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get shipRefreshes => publications.stream;
  final pending = <Completer<CommunityShipsPage>>[];
  final requests =
      <({int offset, String? revision, CommunityShipQuery? query})>[];
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) {
    requests.add((offset: offset, revision: revision, query: query));
    final done = Completer<CommunityShipsPage>();
    pending.add(done);
    return done.future;
  }

  void respond(int index, {String? target, String? revision, int count = 25}) {
    final request = requests[index];
    pending[index].complete(
      CommunityShipsPage.parse({
        'schemaVersion': 1,
        'targetRef': target ?? _target,
        'revision': revision ?? _revision,
        'queryVersion': 2,
        'query': request.query!.toPayload(),
        'offset': request.offset,
        'totalCount': count,
        'matchedCount': count,
        'next': request.offset + 20 < count ? request.offset + 20 : null,
        'ships': List.generate(
          (count - request.offset).clamp(0, 20),
          (i) => shipRow()
            ..['shipRef'] = (request.offset + i)
                .toRadixString(16)
                .padLeft(32, '0'),
        ),
      }),
    );
  }
}

void main() {
  late _Port port;
  late CommunityShipsController model;
  setUp(() {
    port = _Port();
    model = CommunityShipsController(port, _target);
  });
  tearDown(() async {
    model.dispose();
    await port.changes.close();
    await port.publications.close();
  });
  test('hangar publication expires an unmounted organization cache without blanking it', () async {
    final read = model.load();
    port.respond(0);
    await read;
    final previous = model.page;
    port.publications.add(null);
    expect(model.page, same(previous));
    final entered = model.enter();
    expect(port.requests, hasLength(2));
    expect(model.page, same(previous));
    expect(model.busy, isFalse);
    port.respond(1, revision: 'c' * 64);
    await entered;
    expect(model.page!.revision, 'c' * 64);
  });
  test(
    'publication during a read cannot be hidden by the late response freshness',
    () async {
      final read = model.load();
      port.publications.add(null);
      port.respond(0);
      await read;
      final entered = model.enter();
      expect(port.requests, hasLength(2));
      port.respond(1, revision: 'c' * 64);
      await entered;
      expect(model.page!.revision, 'c' * 64);
    },
  );
  test(
    'same-query refresh retains rows while pending and on transport failure',
    () async {
      final initial = model.load();
      port.respond(0);
      await initial;
      final previous = model.page;
      final refresh = model.load();
      expect(model.page, same(previous));
      port.pending[1].completeError(const CommunityFailure('unavailable'));
      await refresh;
      expect(model.page, same(previous));
      expect(model.error, 'unavailable');
      final retry = model.load();
      port.respond(2);
      await retry;
      expect(model.error, isNull);
      expect(model.page!.totalCount, 25);
    },
  );
  test(
    'unchanged background read keeps the same page and coalesces ticks',
    () async {
      final initial = model.load();
      port.respond(0);
      await initial;
      final original = model.page;
      final refresh = model.refreshVisible();
      expect(model.page, same(original));
      expect(model.busy, isFalse);
      await model.refreshVisible();
      expect(port.requests, hasLength(2));
      port.respond(1);
      await refresh;
      expect(model.page, same(original));
      expect(model.refreshing, isFalse);
    },
  );
  test(
    'unchanged revision with changed counts cannot retain stale rows',
    () async {
      final initial = model.load();
      port.respond(0);
      await initial;
      final refresh = model.refreshVisible();
      port.respond(1, count: 1);
      await refresh;
      expect(model.page, isNull);
      expect(model.error, 'dataInvalid');
    },
  );
  test('changed library rebinds current page to its new revision', () async {
    final initial = model.load();
    port.respond(0);
    await initial;
    final next = model.next();
    port.respond(1);
    await next;
    final refresh = model.refreshVisible();
    expect(model.page!.offset, 20);
    port.respond(2, revision: 'e' * 64);
    await Future<void>.delayed(Duration.zero);
    expect(port.requests.last.offset, 20);
    expect(port.requests.last.revision, 'e' * 64);
    port.respond(3, revision: 'e' * 64);
    await refresh;
    expect(model.page!.offset, 20);
    expect(model.page!.revision, 'e' * 64);
  });
  test('removed final page clamps to the last remaining page', () async {
    final initial = model.load();
    port.respond(0);
    await initial;
    final next = model.next();
    port.respond(1);
    await next;
    final refresh = model.refreshVisible();
    port.respond(2, revision: 'e' * 64, count: 1);
    await refresh;
    expect(port.requests, hasLength(3));
    expect(model.page!.offset, 0);
    expect(model.page!.ships, hasLength(1));
  });
  for (final error in [
    'notAllowed',
    'identityUnavailable',
    'refreshRequired',
  ]) {
    test(
      'refresh $error clears old rows and does not automatically retry',
      () async {
        final initial = model.load();
        port.respond(0);
        await initial;
        final refresh = model.refreshVisible();
        port.pending[1].completeError(CommunityFailure(error));
        await refresh;
        expect(model.page, isNull);
        expect(model.error, error);
        await model.refreshVisible();
        expect(port.requests, hasLength(2));
      },
    );
  }
  test(
    'transient background failure keeps rows and recovers on next tick',
    () async {
      final initial = model.load();
      port.respond(0);
      await initial;
      final previous = model.page;
      final refresh = model.refreshVisible();
      port.pending[1].completeError(const CommunityFailure('unavailable'));
      await refresh;
      expect(model.page, same(previous));
      expect(model.error, 'unavailable');
      final retry = model.refreshVisible();
      expect(port.requests, hasLength(3));
      port.respond(2);
      await retry;
      expect(model.error, isNull);
    },
  );
  test('manual query supersedes an in-flight background reply', () async {
    final initial = model.load();
    port.respond(0);
    await initial;
    final refresh = model.refreshVisible();
    final manual = model.load(
      selection: CommunityShipQuery(text: 'new selection'),
    );
    port.respond(2, revision: 'f' * 64);
    await manual;
    port.respond(1, revision: 'e' * 64);
    await refresh;
    expect(model.page!.query!.text, 'new selection');
    expect(model.page!.revision, 'f' * 64);
    expect(model.refreshing, isFalse);
  });
  test('account invalidation rejects a pending refresh', () async {
    final initial = model.load();
    port.respond(0);
    await initial;
    final refresh = model.refreshVisible();
    port.changes.add(null);
    port.respond(1, revision: 'e' * 64);
    await refresh;
    expect(model.page, isNull);
    expect(model.invalidated, isTrue);
    expect(model.refreshing, isFalse);
  });
  test(
    'default WPF query and both page directions stay version bound',
    () async {
      final read = model.load();
      port.respond(0);
      await read;
      expect(model.query.sort, 'spec');
      expect(model.query.descending, isTrue);
      final next = model.next();
      expect(model.page, isNull);
      port.respond(1);
      await next;
      expect(port.requests[1].offset, 20);
      expect(port.requests[1].revision, _revision);
      final previous = model.previous();
      port.respond(2);
      await previous;
      expect(port.requests[2].offset, 0);
      expect(port.requests[2].revision, _revision);
    },
  );
  test(
    'new selection wins over late response and restarts first page',
    () async {
      final old = model.load();
      final selection = CommunityShipQuery(
        text: 'Search',
        filter: 'large',
        sort: 'name',
        descending: false,
      );
      final newer = model.load(selection: selection);
      port.respond(1);
      await newer;
      port.respond(0);
      await old;
      expect(model.page!.query, selection);
      expect(port.requests[1].offset, 0);
      expect(port.requests[1].revision, isNull);
    },
  );
  test(
    'invalidations clear rows and reject a late page without further requests',
    () async {
      final read = model.load();
      port.changes.add(null);
      port.respond(0);
      await read;
      expect(model.page, isNull);
      expect(model.invalidated, isTrue);
      await model.load();
      expect(port.requests.length, 1);
    },
  );
  test(
    'version conflict clears stale rows and requires explicit fresh read',
    () async {
      final read = model.load();
      port.respond(0);
      await read;
      final next = model.next();
      port.pending[1].completeError(const CommunityFailure('shipsChanged'));
      await next;
      expect(model.page, isNull);
      expect(model.error, 'shipsChanged');
      expect(port.requests.length, 2);
      final refresh = model.load();
      port.respond(2, revision: 'f' * 64);
      await refresh;
      expect(port.requests[2].offset, 0);
      expect(port.requests[2].revision, isNull);
      expect(model.error, isNull);
    },
  );
  test(
    'permission loss clears content and prevents same-context retries',
    () async {
      final read = model.load();
      port.pending[0].completeError(const CommunityFailure('notAllowed'));
      await read;
      expect(model.invalidated, isTrue);
      expect(model.page, isNull);
      await model.load();
      expect(port.requests.length, 1);
    },
  );
  test('another organization response is never presented', () async {
    final read = model.load();
    port.respond(0, target: 'f' * 32);
    await read;
    expect(model.page, isNull);
    expect(model.error, 'dataInvalid');
  });
  test(
    'owner avatar is read once per page and cleared with account context',
    () async {
      final media = WorkspaceTestPort();
      addTearDown(media.changes.close);
      var reads = 0;
      final bytes = Uint8List.fromList([1, 2, 3]);
      media.mediaReader = (offset, version) async {
        reads++;
        return mediaChunk(bytes, offset, kind: 'avatar', memberRef: 'd' * 32);
      };
      model.dispose();
      model = CommunityShipsController(port, _target, mediaPort: media);
      final read = model.load();
      port.respond(0);
      await read;
      expect(reads, 1);
      expect(model.avatar('d' * 32), bytes);
      port.changes.add(null);
      expect(model.avatar('d' * 32), isNull);
      expect(model.page, isNull);
      expect(model.mediaFailed, isFalse);
    },
  );
  test(
    'transient avatar failure keeps rows but permission loss removes them',
    () async {
      final media = WorkspaceTestPort();
      addTearDown(media.changes.close);
      model.dispose();
      model = CommunityShipsController(port, _target, mediaPort: media);
      final read = model.load();
      port.respond(0);
      await read;
      expect(model.page, isNotNull);
      expect(model.mediaFailed, isTrue);
      media.mediaReader = (_, _) async =>
          throw const CommunityFailure('notAllowed');
      final refresh = model.load();
      port.respond(1);
      await refresh;
      expect(model.page, isNull);
      expect(model.invalidated, isTrue);
      expect(model.error, 'notAllowed');
    },
  );
  test('late avatar cannot repopulate an invalidated view', () async {
    final media = WorkspaceTestPort();
    addTearDown(media.changes.close);
    final pending = Completer<Map<String, Object?>>();
    final started = Completer<void>();
    media.mediaReader = (_, _) {
      started.complete();
      return pending.future;
    };
    model.dispose();
    model = CommunityShipsController(port, _target, mediaPort: media);
    final read = model.load();
    port.respond(0);
    await started.future;
    expect(model.page, isNotNull);
    port.changes.add(null);
    pending.complete(
      mediaChunk(
        Uint8List.fromList([1]),
        0,
        kind: 'avatar',
        memberRef: 'd' * 32,
      ),
    );
    await read;
    expect(model.avatar('d' * 32), isNull);
    expect(model.page, isNull);
    expect(model.error, 'identityUnavailable');
  });
  test(
    'visible refresh does not interrupt the current owner avatar read',
    () async {
      final media = WorkspaceTestPort();
      addTearDown(media.changes.close);
      final pending = Completer<Map<String, Object?>>();
      final started = Completer<void>();
      media.mediaReader = (_, _) {
        started.complete();
        return pending.future;
      };
      model.dispose();
      model = CommunityShipsController(port, _target, mediaPort: media);
      final read = model.load();
      port.respond(0);
      await started.future;
      await model.refreshVisible();
      expect(port.requests, hasLength(1));
      final bytes = Uint8List.fromList([1]);
      pending.complete(
        mediaChunk(bytes, 0, kind: 'avatar', memberRef: 'd' * 32),
      );
      await read;
      final refresh = model.refreshVisible();
      expect(port.requests, hasLength(2));
      port.respond(1);
      await refresh;
      expect(model.avatar('d' * 32), bytes);
    },
  );
}
