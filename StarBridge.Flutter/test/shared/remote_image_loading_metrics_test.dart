import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../support/remote_image_fixture.dart';

const _url = 'https://hidden.example.test/private-image?token=never-record';
const _etag = '"private-etag-not-logged"';
const _captureDir = String.fromEnvironment(
  'STARBRIDGE_IMAGE_TRANSFER_CAPTURE_DIR',
);
int _captureSequence = 0;

class _RawHttp extends HttpOverrides {}

final class _LocalClient extends Fake implements HttpClient {
  _LocalClient(this.base) : inner = _RawHttp().createHttpClient(null) {
    inner.findProxy = (_) => 'DIRECT';
  }
  final Uri base;
  final HttpClient inner;
  @override
  Duration? get connectionTimeout => inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      inner.getUrl(base.replace(path: url.path, query: url.query));
  @override
  void close({bool force = false}) => inner.close(force: force);
}

final class _Fixture {
  _Fixture._(this.server) {
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    loader = RemoteImageLoader(
      mode: mode,
      now: () => now,
      createClient: () => _LocalClient(base),
    );
    metrics = LoadingMetrics(
      nowUs: () => ++tick,
      write: (event) {
        if (brokenSink) throw StateError('private-error-never-record');
        events.add(event);
      },
    );
    subscription = server.listen((request) => handlers.add(respond(request)));
    addTearDown(close);
  }
  static Future<_Fixture> start() async =>
      _Fixture._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  final HttpServer server;
  final int capture = ++_captureSequence;
  final mode = ImageMode();
  late final RemoteImageLoader loader;
  late final LoadingMetrics metrics;
  late final StreamSubscription<HttpRequest> subscription;
  final events = <Map<String, Object>>[];
  final handlers = <Future<void>>[];
  final flushed = Completer<void>(), release = Completer<void>();
  final bytes = List<int>.filled(4096, 42);
  DateTime now = DateTime.utc(2026, 10, 19);
  int tick = 0, requests = 0, bodies = 0;
  bool redirect = false, compressed = false, holdBody = false;
  bool brokenSink = false, serverClosed = false;

  Future<T> trace<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {loadingMetricsZoneKey: metrics});
  List<Map<String, Object>> get starts =>
      events.where((event) => event['kind'] == 'imageTransferStart').toList();
  List<Map<String, Object>> get ends =>
      events.where((event) => event['kind'] == 'imageTransferEnd').toList();

  Future<void> respond(HttpRequest request) async {
    requests++;
    final response = request.response;
    try {
      response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=60');
      if (redirect && request.uri.path == '/private-image') {
        response.statusCode = HttpStatus.found;
        response.headers.set(
          HttpHeaders.locationHeader,
          '/after-private?signature=never-record',
        );
      } else if (request.headers.value(HttpHeaders.ifNoneMatchHeader) ==
          _etag) {
        response.statusCode = HttpStatus.notModified;
      } else {
        response.headers.set(HttpHeaders.etagHeader, _etag);
        final body = compressed ? gzip.encode(bytes) : bytes;
        response.contentLength = body.length;
        if (compressed) {
          response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        }
        bodies++;
        if (holdBody) {
          response.add(body.sublist(0, 8));
          await response.flush();
          if (!flushed.isCompleted) flushed.complete();
          await release.future;
          response.add(body.sublist(8));
        } else {
          response.add(body);
        }
      }
      await response.close();
    } on SocketException {
      // The actual production loader may abort a response.
    } on HttpException {
      // No external server, account or TLS override participates.
    }
  }

  Future<void> stopServer() async {
    if (serverClosed) return;
    serverClosed = true;
    await server.close(force: true);
    await subscription.cancel();
  }

  Future<void> close() async {
    if (!release.isCompleted) release.complete();
    await loader.retireAsync();
    loader.dispose();
    mode.dispose();
    await stopServer();
    await Future.wait(handlers);
    if (_captureDir.isNotEmpty) {
      final directory = await Directory(_captureDir).create(recursive: true);
      final name = '${directory.path}/fixture-$capture';
      await File('$name.jsonl').writeAsString(
        [
          ...events,
          {'kind': 'stopped', 'us': ++tick},
        ].map(jsonEncode).join('\n'),
      );
      await File('$name.expected.json').writeAsString(
        jsonEncode({
          'source': 'real-loopback-fixture-not-device',
          'serverRequests': requests,
          'serverBodies': bodies,
          'bodyBytes': bytes.length,
          'gzip': compressed,
          'heldBody': holdBody,
          'recorderStopped': metrics.stopped,
        }),
      );
    }
  }
}

void main() {
  test(
    'a measured memory-only hit has capability and no HTTP attempts',
    () async {
      final h = await _Fixture.start();
      expect(await h.loader.load(_url), h.bytes);
      expect(await h.trace(() => h.loader.load(_url)), h.bytes);
      expect(h.requests, 1);
      expect(
        h.events.where((event) => event['kind'] == 'imageTransferMetrics'),
        hasLength(1),
      );
      expect(h.starts, isEmpty);
      expect(h.ends, isEmpty);
    },
  );

  test(
    'stopping the recorder during IO does not cancel the real body',
    () async {
      final h = await _Fixture.start();
      h.holdBody = true;
      final read = h.trace(() => h.loader.load(_url));
      await h.flushed.future.timeout(const Duration(seconds: 3));
      h.metrics.stop();
      h.release.complete();
      expect(await read, h.bytes);
      expect(h.starts, hasLength(1));
      expect(h.ends, isEmpty);
    },
  );

  test(
    'real complete body and memory hit produce one numeric transfer pair',
    () async {
      final h = await _Fixture.start();
      expect(await h.trace(() => h.loader.load(_url)), h.bytes);
      expect(await h.trace(() => h.loader.load(_url)), h.bytes);
      expect(h.requests, 1);
      expect(h.starts, hasLength(1));
      expect(h.ends, hasLength(1));
      final end = h.ends.single;
      expect(end['id'], h.starts.single['id']);
      expect(end['statusCode'], 200);
      expect(end['bodyComplete'], true);
      expect(end['consumedBodyBytes'], h.bytes.length);
      expect(end['encodedResponseBodyBytes'], h.bytes.length);
      expect(end['encoding'], 'encoded');
      final trace = jsonEncode(h.events);
      for (final secret in [
        'hidden.example',
        'private-image',
        'token=',
        'never-record',
        _etag,
      ]) {
        expect(trace, isNot(contains(secret)));
      }
    },
  );

  test('real conditional 304 records zero complete response body without a second body', () async {
    final h = await _Fixture.start();
    expect(await h.trace(() => h.loader.load(_url)), h.bytes);
    h.now = h.now.add(const Duration(minutes: 2));
    expect(await h.trace(() => h.loader.load(_url)), h.bytes);
    expect(h.requests, 2);
    expect(h.bodies, 1);
    expect(h.ends, hasLength(2));
    expect(h.ends.last['statusCode'], 304);
    expect(h.ends.last['bodyComplete'], true);
    expect(h.ends.last['encodedResponseBodyBytes'], 0);
  });

  test('real redirect is a separate incomplete receipt, not a zero-byte full response', () async {
    final h = await _Fixture.start();
    h.redirect = true;
    expect(await h.trace(() => h.loader.load(_url)), h.bytes);
    expect(h.requests, 2);
    expect(h.starts, hasLength(2));
    expect(h.ends, hasLength(2));
    expect(h.ends.first['statusCode'], 302);
    expect(h.ends.first['bodyComplete'], false);
    expect(h.ends.first.containsKey('encodedResponseBodyBytes'), false);
    expect(h.ends.last['encodedResponseBodyBytes'], h.bytes.length);
  });

  test('automatic gzip decoding never labels expanded bytes as encoded network body', () async {
    final h = await _Fixture.start();
    h.compressed = true;
    expect(await h.trace(() => h.loader.load(_url)), h.bytes);
    expect(gzip.encode(h.bytes).length, lessThan(h.bytes.length));
    expect(h.ends, hasLength(1));
    expect(h.ends.single['bodyComplete'], true);
    expect(h.ends.single['consumedBodyBytes'], h.bytes.length);
    expect(h.ends.single['encoding'], 'decoded');
    expect(h.ends.single.containsKey('encodedResponseBodyBytes'), false);
  });

  test(
    'header size rejection does not claim a complete zero-byte transfer',
    () async {
      final h = await _Fixture.start();
      expect(await h.trace(() => h.loader.load(_url, maxBytes: 2)), isNull);
      expect(h.ends, hasLength(1));
      expect(h.ends.single['statusCode'], 200);
      expect(h.ends.single['bodyComplete'], false);
      expect(h.ends.single.containsKey('encodedResponseBodyBytes'), false);
    },
  );

  test(
    'suspension still joins actual IO and leaves incomplete body explicit',
    () async {
      final h = await _Fixture.start();
      h.holdBody = true;
      final read = h.trace(() => h.loader.load(_url));
      await h.flushed.future.timeout(const Duration(seconds: 3));
      await h.loader.suspendAndDrain().timeout(const Duration(seconds: 3));
      expect(await read, isNull);
      expect(h.ends, hasLength(1));
      expect(h.ends.single['bodyComplete'], false);
      expect(h.ends.single.containsKey('encodedResponseBodyBytes'), false);
    },
  );

  test(
    'connection failure before headers remains an unknown incomplete attempt',
    () async {
      final h = await _Fixture.start();
      await h.stopServer();
      expect(await h.trace(() => h.loader.load(_url)), isNull);
      expect(h.starts, hasLength(1));
      expect(h.ends, hasLength(1));
      expect(h.ends.single['statusCode'], 0);
      expect(h.ends.single['bodyComplete'], false);
      expect(h.ends.single.containsKey('encodedResponseBodyBytes'), false);
    },
  );

  for (final recorder in ['absent', 'stopped', 'broken']) {
    test('$recorder recorder never changes an actual HTTP result', () async {
      final h = await _Fixture.start();
      if (recorder == 'stopped') h.metrics.stop();
      h.brokenSink = recorder == 'broken';
      expect(
        await (recorder == 'absent'
            ? h.loader.load(_url)
            : h.trace(() => h.loader.load(_url))),
        h.bytes,
      );
      expect(h.requests, 1);
      expect(h.events, isEmpty);
    });
  }
}
