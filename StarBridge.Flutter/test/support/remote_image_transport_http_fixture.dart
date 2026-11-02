// Loopback-only HTTP/1.1 evidence. Fixed fixture URIs, no TLS override in the
// product, account, credential, private endpoint or visible client.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'remote_image_fixture.dart';

typedef ImageHttpProbe = ({
  Future<Uint8List?> Function(String) load,
  Future<void> Function() retire,
  void Function() dispose,
});
typedef ImageHttpProbeFactory = ImageHttpProbe Function(
  ImageMode mode,
  DateTime Function() now,
  HttpClient Function() createClient,
);

class _RawHttp extends HttpOverrides {}

class _LoopbackClient extends Fake implements HttpClient {
  _LoopbackClient(this.base) : inner = _RawHttp().createHttpClient(null) {
    inner.findProxy = (_) => 'DIRECT';
  }
  final Uri base;
  final HttpClient inner;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) =>
      inner.getUrl(base.replace(path: uri.path, query: uri.query));
  @override
  void close({bool force = false}) => inner.close(force: force);
}

class _Fixture {
  _Fixture._(this.server, ImageHttpProbeFactory create) {
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    loader = create(mode, () => now, () => _LoopbackClient(base));
    subscription = server.listen((request) => unawaited(respond(request)));
    addTearDown(() async {
      if (!slowRelease.isCompleted) slowRelease.complete();
      if (!healthyRelease.isCompleted) healthyRelease.complete();
      await loader.retire();
      loader.dispose();
      mode.dispose();
      await server.close(force: true);
      await subscription.cancel();
    });
  }
  static Future<_Fixture> start(ImageHttpProbeFactory create) async =>
      _Fixture._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        create,
      );
  final HttpServer server;
  final mode = ImageMode();
  late final ImageHttpProbe loader;
  late final StreamSubscription<HttpRequest> subscription;
  DateTime now = DateTime.utc(2026, 10, 17);
  final slowAccepted = Completer<void>(), healthyAccepted = Completer<void>();
  final slowRelease = Completer<void>(), healthyRelease = Completer<void>();
  final ports = <int>{};
  int requests = 0, bodies = 0, validations = 0;

  Future<void> respond(HttpRequest request) async {
    requests++;
    final port = request.connectionInfo?.remotePort;
    if (port != null) ports.add(port);
    final response = request.response;
    try {
      if (request.uri.path == '/slow') {
        slowAccepted.complete();
        await slowRelease.future;
      }
      if (request.uri.path == '/healthy') {
        healthyAccepted.complete();
        await healthyRelease.future;
      }
      response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=60');
      response.headers.set(HttpHeaders.etagHeader, '"fixture"');
      if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == '"fixture"') {
        validations++;
        response.statusCode = HttpStatus.notModified;
      } else {
        bodies++;
        response.contentLength = 3;
        response.add([1, 2, 3]);
      }
      await response.close();
    } on SocketException {
      // A deliberately timed-out client closed only its own request.
    } on HttpException {
      // The original implementation also aborts the healthy connection.
    }
  }
}

void imageTransportHttpCases(
  ImageHttpProbeFactory create, {
  bool timeoutOnly = false,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real HTTP timeout cannot close another image connection', () async {
    final fixture = await _Fixture.start(create);
    final slow = fixture.loader.load('https://media.example.test/slow');
    await fixture.slowAccepted.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(seconds: 5));
    final healthy = fixture.loader.load('https://media.example.test/healthy');
    await fixture.healthyAccepted.future.timeout(const Duration(seconds: 4));
    expect(await slow, isNull);
    fixture.healthyRelease.complete();
    expect(await healthy, orderedEquals([1, 2, 3]));
    expect(fixture.requests, 2);
  }, timeout: const Timeout(Duration(seconds: 25)));
  if (timeoutOnly) return;

  test(
    'real HTTP eight sequential images reuse one keep-alive connection',
    () async {
      final fixture = await _Fixture.start(create);
      for (var i = 0; i < 8; i++) {
        expect(
          await fixture.loader.load('https://media.example.test/image?i=$i'),
          orderedEquals([1, 2, 3]),
        );
      }
      expect(fixture.requests, 8);
      expect(fixture.bodies, 8);
      expect(fixture.ports, hasLength(1));
    },
  );

  test(
    'real HTTP304 consumes no replacement body and reuses its connection',
    () async {
      final fixture = await _Fixture.start(create);
      const source = 'https://media.example.test/image';
      for (var i = 0; i < 4; i++) {
        expect(await fixture.loader.load(source), orderedEquals([1, 2, 3]));
        fixture.now = fixture.now.add(const Duration(minutes: 2));
      }
      expect(fixture.requests, 4);
      expect(fixture.bodies, 1);
      expect(fixture.validations, 3);
      expect(fixture.ports, hasLength(1));
    },
  );
}
