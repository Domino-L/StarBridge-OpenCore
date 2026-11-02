// Internal transport fixture only: no network, account, window or user data.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../support/remote_image_fixture.dart';

const _slow = 'https://media.example.test/slow';
const _healthy = 'https://media.example.test/healthy';

class _Deadline implements Timer {
  _Deadline(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

Future<void> _retire(WidgetTester tester, RemoteImageLoader loader) async {
  final retirement = loader.retireAsync();
  // Fixture IO belongs to the widget clock. Flush its cancellation work before
  // awaiting completion from the framework's outer teardown zone.
  await tester.pump();
  await retirement;
  loader.dispose();
}

class _Headers extends Fake implements HttpHeaders {
  @override
  List<String>? operator [](String name) => null;
}

class _Body extends Stream<List<int>> implements HttpClientResponse {
  final controller = StreamController<List<int>>();
  @override
  final headers = _Headers();
  @override
  int get statusCode => 200;
  @override
  int get contentLength => -1;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.uri, {this.ignoreAbort = false});
  final bool ignoreAbort;
  @override
  final Uri uri;
  @override
  final headers = _Headers();
  @override
  bool followRedirects = true;
  final reply = Completer<HttpClientResponse>();
  _Body? body;
  int aborts = 0;
  @override
  Future<HttpClientResponse> close() => reply.future;
  void succeed(List<int> bytes) {
    final response = body = _Body();
    reply.complete(response);
    response.controller.add(bytes);
    unawaited(response.controller.close());
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts++;
    if (ignoreAbort) return;
    if (!reply.isCompleted) {
      reply.completeError(exception ?? const HttpException('fixture aborted'));
    } else if (body != null && !body!.controller.isClosed) {
      body!.controller.addError(const HttpException('fixture aborted'));
      unawaited(body!.controller.close());
    }
  }
}

class _Client extends Fake implements HttpClient {
  _Client({
    this.holdAcquisition = false,
    this.ignoreClose = false,
    this.ignoreRequestAbort = false,
  });
  final bool holdAcquisition, ignoreClose, ignoreRequestAbort;
  final acquisition = Completer<void>();
  @override
  Duration? connectionTimeout;
  final requests = <_Request>[];
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    if (holdAcquisition) await acquisition.future;
    if (closed) throw const HttpException('fixture client closed');
    final request = _Request(uri, ignoreAbort: ignoreRequestAbort);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
    if (holdAcquisition && !ignoreClose && !acquisition.isCompleted) {
      acquisition.complete();
    }
    if (force) {
      for (final request in requests) {
        request.abort();
      }
    }
  }
}

void main() {
  testWidgets('one image header timeout leaves another image alive', (
    tester,
  ) async {
    final mode = ImageMode();
    final clients = <_Client>[];
    final loader = RemoteImageLoader(
      mode: mode,
      createClient: () {
        final client = _Client();
        clients.add(client);
        return client;
      },
    );
    addTearDown(() async {
      await _retire(tester, loader);
      mode.dispose();
    });
    final slow = loader.load(_slow);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    final healthy = loader.load(_healthy);
    await tester.pump();
    final request = clients
        .expand((client) => client.requests)
        .singleWhere((request) => request.uri.toString() == _healthy);
    await tester.pump(const Duration(seconds: 1));
    expect(await slow, isNull);
    expect(request.aborts, 0, reason: 'Another image owns its own deadline');
    request.succeed([1, 2, 3]);
    await tester.pump();
    expect(await healthy, orderedEquals([1, 2, 3]));
    expect(loader.cached(_healthy), orderedEquals([1, 2, 3]));
  });

  for (final stage in ['connect', 'body']) {
    testWidgets('one image $stage timeout leaves another image alive', (
      tester,
    ) async {
      final mode = ImageMode();
      final clients = <_Client>[];
      final loader = RemoteImageLoader(
        mode: mode,
        createClient: () {
          final client = _Client(
            holdAcquisition: clients.isEmpty && stage == 'connect',
          );
          clients.add(client);
          return client;
        },
      );
      addTearDown(() async {
        await _retire(tester, loader);
        mode.dispose();
      });
      final slow = loader.load(_slow);
      await tester.pump();
      if (stage == 'body') {
        final request = clients.single.requests.single;
        final response = request.body = _Body();
        request.reply.complete(response);
        response.controller.add([9]);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 9));
      final healthy = loader.load(_healthy);
      await tester.pump();
      final request = clients
          .expand((client) => client.requests)
          .singleWhere((request) => request.uri.toString() == _healthy);
      final epoch = loader.readEpoch;
      await tester.pump(const Duration(seconds: 1));
      expect(await slow, isNull);
      expect(loader.readEpoch, epoch);
      expect(request.aborts, 0);
      request.succeed([1, 2, 3]);
      await tester.pump();
      expect(await healthy, orderedEquals([1, 2, 3]));
      expect(loader.cached(_slow), isNull);
    });
  }

  testWidgets('sequential successful images reuse their idle client', (
    tester,
  ) async {
    final mode = ImageMode();
    final clients = <_Client>[];
    final loader = RemoteImageLoader(
      mode: mode,
      createClient: () {
        final client = _Client();
        clients.add(client);
        return client;
      },
    );
    addTearDown(() async {
      await _retire(tester, loader);
      mode.dispose();
    });
    for (var i = 0; i < 8; i++) {
      final fetch = loader.load('$_healthy?$i');
      await tester.pump();
      expect(clients, hasLength(1));
      clients.single.requests.last.succeed([i + 1]);
      await tester.pump();
      expect(await fetch, orderedEquals([i + 1]));
    }
    expect(clients.single.closed, isFalse);
    expect(clients.single.requests, hasLength(8));
    await loader.suspendAndDrain();
    expect(clients.single.closed, isTrue);
  });

  testWidgets('borrowed loaders share six active slots and a bounded queue', (
    tester,
  ) async {
    final mode = ImageMode();
    final clients = <_Client>[];
    final root = RemoteImageLoader(
      mode: mode,
      createClient: () {
        final client = _Client();
        clients.add(client);
        return client;
      },
    );
    final child = root.fork(), sibling = root.fork();
    // Actual retirement is awaited in this test's clock zone below. Do not
    // await that fake-zone future again from the outer teardown zone.
    addTearDown(() {
      root.dispose();
      child.dispose();
      sibling.dispose();
      mode.dispose();
    });
    final active = List.generate(6, (i) => root.load('$_slow?$i'));
    final abandoned = [
      child.load('$_slow?child0'),
      child.load('$_slow?child1'),
    ];
    final next = sibling.load(_healthy);
    await tester.pump();
    expect(clients, hasLength(6));
    final childRetirement = child.retireAsync();
    await tester.pump();
    await childRetirement;
    expect(await Future.wait(abandoned), everyElement(isNull));
    expect(clients.expand((client) => client.requests), hasLength(6));
    expect(clients.every((client) => !client.closed), isTrue);
    clients.first.requests.first.succeed([1]);
    await tester.pump();
    expect(clients, hasLength(6));
    final request = clients
        .expand((client) => client.requests)
        .singleWhere((request) => request.uri.toString() == _healthy);
    request.succeed([2]);
    await tester.pump();
    expect(await next, orderedEquals([2]));
    final rootRetirement = root.retireAsync();
    await tester.pump();
    await rootRetirement;
    final results = await Future.wait(active);
    expect(results.first, orderedEquals([1]));
    expect(results.skip(1), everyElement(isNull));
  });

  testWidgets('queued expiry never starts HTTP after late physical exit', (
    tester,
  ) async {
    final mode = ImageMode();
    final clients = <_Client>[];
    final loader = RemoteImageLoader(
      mode: mode,
      createClient: () {
        final client = _Client(holdAcquisition: true, ignoreClose: true);
        clients.add(client);
        return client;
      },
    );
    addTearDown(() async {
      for (final client in clients) {
        if (!client.acquisition.isCompleted) client.acquisition.complete();
      }
      await _retire(tester, loader);
      mode.dispose();
    });
    var visibleFinished = 0;
    final active = List.generate(
      6,
      (i) => loader.load('$_slow?$i').then((bytes) {
        visibleFinished++;
        return bytes;
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final queued = loader.load(_healthy);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(clients, hasLength(6), reason: 'Cancelled IO still owns its permit');
    expect(
      visibleFinished,
      6,
      reason:
          'UI deadline does not wait for physical cancellation acknowledgement',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(await queued, isNull);
    var drained = false;
    final drain = loader.suspendAndDrain().then((_) => drained = true);
    await tester.pump();
    expect(drained, isFalse);
    for (final client in clients) {
      client.acquisition.complete();
    }
    await tester.pump();
    expect(await Future.wait(active), everyElement(isNull));
    await drain;
    expect(clients, hasLength(6));
    expect(clients.expand((client) => client.requests), isEmpty);
    expect(loader.cached(_healthy), isNull);
  });

  test(
    'late body after UI expiry cannot publish or finish drain early',
    () async {
      final deadlines = <_Deadline>[];
      await runZoned(
        () async {
          final mode = ImageMode();
          final client = _Client(ignoreRequestAbort: true);
          final loader = RemoteImageLoader(
            mode: mode,
            createClient: () => client,
          );
          _Body? response;
          try {
            final fetch = loader.load(_slow);
            await Future<void>.delayed(Duration.zero);
            final request = client.requests.single;
            response = request.body = _Body();
            request.reply.complete(response);
            response.controller.add([8]);
            await Future<void>.delayed(Duration.zero);
            expect(deadlines, hasLength(1));
            deadlines.single.fire();
            expect(await fetch, isNull);
            expect(loader.cached(_slow), isNull);
            var drained = false;
            final drain = loader.suspendAndDrain().then((_) => drained = true);
            await Future<void>.delayed(Duration.zero);
            expect(drained, isFalse);
            response.controller.add([9]);
            await drain;
            expect(drained, isTrue);
            expect(loader.cached(_slow), isNull);
          } finally {
            final body = response;
            if (body != null && !body.controller.isClosed) {
              await body.controller.close();
            }
            await loader.retireAsync();
            loader.dispose();
            mode.dispose();
          }
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration == const Duration(seconds: 10)) {
              final timer = _Deadline(() => zone.runGuarded(callback));
              deadlines.add(timer);
              return timer;
            }
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
    },
  );
}
