// Internal loopback transport only. No live account, CDN or client launch.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

// 2026-10-21 (build 15, official candidate): the RSI fleet banner never loaded;
// 40/40 night samples had no remote image transfer at all and the Host image
// disk cache directory was never created. That build compiled without
// connection modes, as a Host without the mode route still does, so the
// mode snapshot stays the default "unsupported" with scope 0. Every other
// online reader asks allowsOnlineTraffic (true there); the image loader alone
// required state == online and treated itself as offline forever.

const _source =
    'https://cdn.example.test/static/images/organization/banner.jpg';
const _bytes = [0xFF, 0xD8, 0xFF, 0xD9];

class _RawHttp extends HttpOverrides {}

final class _LoopbackClient extends Fake implements HttpClient {
  _LoopbackClient(this.base) : inner = _RawHttp().createHttpClient(null) {
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

/// A mode owner with no connection modes: online traffic allowed.
final class _NoModes extends ChangeNotifier implements ConnectionModeControl {
  bool allowed = true;
  @override
  bool busy = false;
  @override
  bool failed = false;
  @override
  ConnectionModeSnapshot get snapshot => const ConnectionModeSnapshot();
  @override
  bool get allowsOnlineTraffic => allowed && !busy && !failed;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RemoteImageLoader, _NoModes, List<String>)> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final subscription = server.listen((request) async {
      requests.add(request.uri.path);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.cacheControlHeader, 'max-age=60')
        ..add(_bytes);
      await request.response.close();
    });
    final mode = _NoModes();
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final loader = RemoteImageLoader(
      mode: mode,
      createClient: () => _LoopbackClient(base),
    );
    addTearDown(() async {
      await loader.retireAsync();
      loader.dispose();
      mode.dispose();
      await subscription.cancel();
      await server.close(force: true);
    });
    return (loader, mode, requests);
  }

  test('a mode owner without connection modes loads remote images', () async {
    final (loader, _, requests) = await start();
    expect(
      loader.online,
      isTrue,
      reason: 'The image loader treats a missing mode route as offline.',
    );
    expect(
      await loader.load(_source, kind: RemoteImageResourceKind.organization),
      _bytes,
    );
    expect(requests, ['/static/images/organization/banner.jpg']);
  });

  test('the mode owner can still stop online image traffic', () async {
    final (loader, mode, requests) = await start();
    mode.allowed = false;
    expect(loader.online, isFalse);
    expect(
      await loader.load(_source, kind: RemoteImageResourceKind.organization),
      isNull,
    );
    expect(requests, isEmpty);
  });
}
