// Internal transport fixture only: no account, live HTTP or client launch.
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

const _url = 'https://cdn.example.test/image.png';
const _oldBytes = [1, 2, 3];

final class _Mode extends ChangeNotifier implements ConnectionModeControl {
  ConnectionModeState state = ConnectionModeState.online;
  @override
  bool busy = false;
  @override
  bool failed = false;
  @override
  ConnectionModeSnapshot get snapshot =>
      ConnectionModeSnapshot(state: state, scope: 1, revision: 1);
  @override
  bool get allowsOnlineTraffic =>
      !busy && !failed && state == ConnectionModeState.online;
  @override
  bool get canEnterOffline => allowsOnlineTraffic;
  void change(ConnectionModeState value) {
    state = value;
    notifyListeners();
  }

  @override
  Future<bool> enterOffline() async {
    change(ConnectionModeState.offline);
    return true;
  }
}

final class _Headers extends Fake implements HttpHeaders {
  _Headers([Map<String, String> initial = const {}]) {
    for (final entry in initial.entries) {
      set(entry.key, entry.value);
    }
  }
  final values = <String, List<String>>{};
  @override
  List<String>? operator [](String name) => values[name.toLowerCase()];
  @override
  String? value(String name) => values[name.toLowerCase()]?.single;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }
}

final class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.body, {String? etag, String? control})
    : headers = _Headers({
        HttpHeaders.etagHeader: ?etag,
        HttpHeaders.cacheControlHeader: ?control,
      });
  @override
  final int statusCode;
  final List<int> body;
  @override
  final _Headers headers;
  int bodyBytesDelivered = 0;
  @override
  int get contentLength => body.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(body).listen(
    (chunk) {
      bodyBytesDelivered += chunk.length;
      onData?.call(chunk);
    },
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Request extends Fake implements HttpClientRequest {
  _Request(this.uri, this.response);
  @override
  final Uri uri;
  final Future<_Response> Function(_Headers) response;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() => response(headers);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

final class _Client extends Fake implements HttpClient {
  final replies = Queue<Future<_Response> Function(_Headers)>();
  final requests = <_Request>[];
  @override
  Duration? connectionTimeout;
  _Response reply(int status, List<int> body, {String? etag, String? control}) {
    final response = _Response(status, body, etag: etag, control: control);
    replies.add((_) async => response);
    return response;
  }

  _ConditionalOrigin conditional(String etag, List<int> body) {
    final origin = _ConditionalOrigin(etag, body);
    replies.add(origin.respond);
    return origin;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (replies.isEmpty) throw StateError('Fixture response required');
    final request = _Request(url, replies.removeFirst());
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
}

// The fake origin chooses a full body unless the actual request supplied its
// validator. Returning304 unconditionally would hide repeated body downloads.
final class _ConditionalOrigin {
  _ConditionalOrigin(this.etag, List<int> body)
    : full = _Response(200, body, etag: etag),
      unchanged = _Response(304, const [], etag: etag);
  final String etag;
  final _Response full, unchanged;
  Future<_Response> respond(_Headers request) async =>
      request.value(HttpHeaders.ifNoneMatchHeader) == etag ? unchanged : full;
}

final class _Harness {
  _Harness() {
    loader = RemoteImageLoader(
      mode: mode,
      createClient: () => client,
      now: () => now,
    );
    addTearDown(() async {
      await loader.retireAsync();
      loader.dispose();
      mode.dispose();
    });
  }
  final mode = _Mode();
  final client = _Client();
  DateTime now = DateTime.utc(2026, 10, 17);
  late final RemoteImageLoader loader;
  void expire() => now = now.add(const Duration(minutes: 6));
  String? validator(int request) =>
      client.requests[request].headers.value(HttpHeaders.ifNoneMatchHeader);
  Future<void> seed({String? etag = '"old"', String? control}) async {
    client.reply(200, _oldBytes, etag: etag, control: control);
    expect(await loader.load(_url), _oldBytes);
  }
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 50 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _metadataBoundaryCases();
  for (final etag in ['"old"', 'W/"old"']) {
    final kind = etag.startsWith('W/') ? 'weak' : 'strong';
    test('expired $kind image validates and renews on304', () async {
      final h = _Harness();
      await h.seed(etag: etag);
      h.expire();
      final origin = h.client.conditional(etag, _oldBytes);
      expect(await h.loader.load(_url), _oldBytes);
      expect(
        origin.full.bodyBytesDelivered,
        0,
        reason: 'Unchanged image body must not be downloaded again',
      );
      expect(h.validator(1), etag);
      expect(origin.unchanged.bodyBytesDelivered, 0);
      h.now = h.now.add(const Duration(seconds: 20));
      h.client.reply(200, const [9]); // Detect an erroneous failure10s retry.
      expect(await h.loader.load(_url), _oldBytes);
      expect(h.client.requests, hasLength(2));
    });
  }
  test('concurrent expired consumers share one conditional request', () async {
    final h = _Harness();
    await h.seed();
    h.expire();
    final response = Completer<_Response>();
    h.client.replies.add((_) => response.future);
    addTearDown(() {
      if (!response.isCompleted) response.complete(_Response(304, const []));
    });
    final first = h.loader.load(_url), second = h.loader.load(_url);
    expect(identical(first, second), true);
    await _until(() => h.client.requests.length == 2);
    expect(h.validator(1), '"old"');
    response.complete(_Response(304, const []));
    expect(await first, _oldBytes);
    expect(await second, _oldBytes);
  });
  test('200 replaces image bytes and the next validator together', () async {
    final h = _Harness();
    await h.seed();
    h.expire();
    h.client.reply(200, const [4, 5], etag: '"new"');
    expect(await h.loader.load(_url), [4, 5]);
    expect(h.validator(1), '"old"');
    h.expire();
    h.client.reply(304, const []);
    expect(await h.loader.load(_url), [4, 5]);
    expect(h.validator(2), '"new"');
  });
  test(
    'missing ETag performs full GET and does not invent a validator',
    () async {
      final h = _Harness();
      await h.seed(etag: null);
      h.expire();
      h.client.reply(200, const [4]);
      expect(await h.loader.load(_url), [4]);
      expect(h.validator(1), isNull);
    },
  );
  test('replacement200 without ETag retires the older validator', () async {
    final h = _Harness();
    await h.seed();
    h.expire();
    h.client.reply(200, const [4]);
    expect(await h.loader.load(_url), [4]);
    h.expire();
    h.client.reply(200, const [5]);
    expect(await h.loader.load(_url), [5]);
    expect(h.validator(2), isNull);
  });
  for (final invalid in [
    'unquoted',
    '"embedded"quote"',
    '"bad\r\nheader"',
    '"${List.filled(2048, 'x').join()}"',
  ]) {
    test('unusable ETag does not discard valid image or get forwarded '
        '${invalid.length}', () async {
      final h = _Harness();
      await h.seed(etag: invalid);
      h.expire();
      h.client.reply(200, const [4]);
      expect(await h.loader.load(_url), [4]);
      expect(h.validator(1), isNull);
    });
  }
  for (final variant in ['source', 'limit', 'redirects']) {
    test('validator does not cross the $variant cache-key boundary', () async {
      final h = _Harness();
      await h.seed();
      h.expire();
      h.client.reply(200, const [4], etag: '"other"');
      expect(
        await h.loader.load(
          variant == 'source' ? '$_url?other=1' : _url,
          maxBytes: variant == 'limit' ? 1024 : 4 * 1024 * 1024,
          followRedirects: variant != 'redirects',
        ),
        [4],
      );
      expect(h.validator(1), isNull);
    });
  }
  test('clear retires retained bytes and validators together', () async {
    final h = _Harness();
    await h.seed();
    h.loader.clear();
    expect(h.loader.cached(_url), isNull);
    h.client.reply(200, const [4]);
    expect(await h.loader.load(_url), [4]);
    expect(h.validator(1), isNull);
  });
  test(
    'unsolicited304 does not count as successful freshness renewal',
    () async {
      final h = _Harness();
      await h.seed(etag: null);
      h.expire();
      h.client.reply(304, const []);
      await h.loader.load(_url);
      expect(h.validator(1), isNull);
      h.now = h.now.add(const Duration(seconds: 11));
      h.client.reply(200, const [4]);
      expect(await h.loader.load(_url), [4]);
      expect(h.client.requests, hasLength(3));
    },
  );
  test('304 without any stored body cannot create content', () async {
    final h = _Harness();
    h.client.reply(304, const []);
    expect(await h.loader.load(_url), isNull);
    expect(h.loader.cached(_url), isNull);
    expect(h.validator(0), isNull);
  });
  test(
    'transient failure keeps old display and retries with its validator',
    () async {
      final h = _Harness();
      await h.seed();
      h.expire();
      h.client.reply(503, const []);
      expect(await h.loader.load(_url), _oldBytes);
      h.now = h.now.add(const Duration(seconds: 11));
      h.client.reply(304, const []);
      expect(await h.loader.load(_url), _oldBytes);
      expect(h.validator(1), '"old"');
      expect(h.validator(2), '"old"');
    },
  );
  for (final status in [401, 403, 404, 410]) {
    test(
      'explicit$status withdraws retained bytes instead of304 reuse',
      () async {
        final h = _Harness();
        await h.seed();
        h.expire();
        h.client.reply(status, const []);
        expect(await h.loader.load(_url), isNull);
        expect(h.loader.cached(_url), isNull);
        h.now = h.now.add(const Duration(seconds: 11));
        h.client.reply(200, const [4]);
        expect(await h.loader.load(_url), [4]);
        expect(h.validator(2), isNull);
      },
    );
  }
  test('no-store response is displayed once and not retained', () async {
    final h = _Harness();
    await h.seed(control: 'private, no-store');
    expect(h.loader.cached(_url), isNull);
    h.client.reply(200, const [4]);
    expect(await h.loader.load(_url), [4]);
    expect(h.validator(1), isNull);
  });
  test('no-cache retains bytes but requires conditional validation', () async {
    final h = _Harness();
    await h.seed(control: 'no-cache');
    h.client.reply(304, const [], control: 'no-cache');
    expect(await h.loader.load(_url), _oldBytes);
    expect(h.client.requests, hasLength(2));
    expect(h.validator(1), '"old"');
    h.client.reply(304, const [], control: 'no-cache');
    expect(await h.loader.load(_url), _oldBytes);
    expect(h.client.requests, hasLength(3));
  });
  test('server max-age shortens the application freshness ceiling', () async {
    final h = _Harness();
    await h.seed(control: 'max-age=60');
    h.now = h.now.add(const Duration(seconds: 61));
    h.client.reply(304, const []);
    expect(await h.loader.load(_url), _oldBytes);
    expect(h.client.requests, hasLength(2));
    expect(h.validator(1), '"old"');
  });
  test(
    'offline keeps old pixels without IO and validates on online resume',
    () async {
      final h = _Harness();
      await h.seed();
      h.mode.change(ConnectionModeState.offline);
      h.expire();
      expect(await h.loader.load(_url), _oldBytes);
      expect(h.client.requests, hasLength(1));
      h.mode.change(ConnectionModeState.online);
      h.client.reply(304, const []);
      expect(await h.loader.load(_url), _oldBytes);
      expect(h.validator(1), '"old"');
    },
  );
  test('late304 after pause cannot mark the old entry fresh', () async {
    final h = _Harness();
    await h.seed();
    h.expire();
    final response = Completer<_Response>();
    h.client.replies.add((_) => response.future);
    addTearDown(() {
      if (!response.isCompleted) response.complete(_Response(304, const []));
    });
    final fetching = h.loader.load(_url);
    await _until(() => h.client.requests.length == 2);
    h.mode.change(ConnectionModeState.offline);
    response.complete(_Response(304, const []));
    await fetching;
    h.mode.change(ConnectionModeState.online);
    h.client.reply(304, const []);
    expect(await h.loader.load(_url), _oldBytes);
    expect(h.client.requests, hasLength(3));
    expect(h.validator(2), '"old"');
  });
}

void _metadataBoundaryCases() {
  test('ambiguous Age does not lose the image or grant freshness', () async {
    final h = _Harness();
    final response = h.client.reply(
      200,
      _oldBytes,
      etag: '"old"',
      control: 'max-age=60',
    );
    response.headers.values[HttpHeaders.ageHeader] = ['10', '20'];
    expect(await h.loader.load(_url), _oldBytes);
    h.client.reply(304, const []);
    expect(await h.loader.load(_url), _oldBytes);
    expect(h.client.requests, hasLength(2));
  });
  test('ambiguous optional ETag does not discard a valid200 body', () async {
    final h = _Harness();
    final response = h.client.reply(200, _oldBytes);
    response.headers.values[HttpHeaders.etagHeader] = ['"a"', '"b"'];
    expect(await h.loader.load(_url), _oldBytes);
    h.expire();
    h.client.reply(200, const [4]);
    expect(await h.loader.load(_url), [4]);
    expect(h.validator(1), isNull);
  });
  for (final control in ['no-store', 'no-cache', 'max-age=0']) {
    test(
      '$control denial does not become a negative cached response',
      () async {
        final h = _Harness();
        await h.seed();
        h.expire();
        h.client.reply(403, const [], control: control);
        expect(await h.loader.load(_url), isNull);
        expect(h.loader.cached(_url), isNull);
        h.client.reply(200, const [4]);
        expect(await h.loader.load(_url), [4]);
        expect(h.validator(2), isNull);
      },
    );
  }
  test(
    '304 without cache directives keeps the existing freshness ceiling',
    () async {
      final h = _Harness();
      await h.seed(control: 'max-age=60');
      for (var i = 0; i < 2; i++) {
        h.now = h.now.add(const Duration(seconds: 61));
        h.client.reply(304, const []);
        expect(await h.loader.load(_url), _oldBytes);
      }
      expect(h.client.requests, hasLength(3));
    },
  );
  test(
    'no-cache transient failure cannot re-expose old cached pixels',
    () async {
      final h = _Harness();
      await h.seed(control: 'no-cache');
      h.client.reply(503, const []);
      expect(await h.loader.load(_url), isNull);
      expect(h.loader.cached(_url), isNull);
      h.mode.change(ConnectionModeState.offline);
      expect(await h.loader.load(_url), isNull);
    },
  );
  test('no-store on304 retires both old bytes and the validator', () async {
    final h = _Harness();
    await h.seed();
    h.expire();
    h.client.reply(304, const [], control: 'no-store');
    expect(await h.loader.load(_url), _oldBytes);
    expect(h.loader.cached(_url), isNull);
    h.client.reply(200, const [4]);
    expect(await h.loader.load(_url), [4]);
    expect(h.validator(2), isNull);
  });
  test('Age reduces the server freshness interval', () async {
    final h = _Harness();
    final response = h.client.reply(
      200,
      _oldBytes,
      etag: '"old"',
      control: 'max-age=60',
    );
    response.headers.set(HttpHeaders.ageHeader, '55');
    expect(await h.loader.load(_url), _oldBytes);
    h.now = h.now.add(const Duration(seconds: 6));
    h.client.reply(304, const []);
    expect(await h.loader.load(_url), _oldBytes);
    expect(h.client.requests, hasLength(2));
    expect(h.validator(1), '"old"');
  });
  test('a borrowed window cannot reuse another window validator', () async {
    final h = _Harness();
    await h.seed();
    final borrowed = h.loader.fork();
    addTearDown(borrowed.dispose);
    h.client.reply(200, const [4]);
    expect(await borrowed.load(_url), [4]);
    expect(h.validator(1), isNull);
  });
  test('304 for a different opaque tag cannot renew freshness', () async {
    final h = _Harness();
    await h.seed();
    h.expire();
    h.client.reply(304, const [], etag: '"different"');
    await h.loader.load(_url);
    h.now = h.now.add(const Duration(seconds: 11));
    h.client.reply(200, const [4]);
    expect(await h.loader.load(_url), [4]);
    expect(h.client.requests, hasLength(3));
  });
}
