// Internal loopback transport only. No live account, CDN, TLS bypass in product,
// or client launch. The injected test client maps a fixed public fixture URI.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_images.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';

import '../support/remote_image_fixture.dart';
import '../app/menu_overlay/menu_chat_media_test.dart' show photo;

const _source = 'https://media.example.test/image';
const _tag = '"same-version"';
const _original = [1, 2, 3];
const _replacement = [4, 5, 6];

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

final class _HttpFixture {
  _HttpFixture._(this.server) {
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    loader = RemoteImageLoader(
      mode: mode,
      now: () => now,
      createClient: () => _LoopbackClient(base),
    );
    subscription = server.listen((request) => unawaited(_respond(request)));
    addTearDown(() async {
      await loader.retireAsync();
      loader.dispose();
      mode.dispose();
      await server.close(force: true);
      await subscription.cancel();
    });
  }
  static Future<_HttpFixture> start() async =>
      _HttpFixture._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  final HttpServer server;
  final mode = ImageMode();
  late final RemoteImageLoader loader;
  late final StreamSubscription<HttpRequest> subscription;
  DateTime now = DateTime.utc(2026, 10, 17);
  bool redirect = false, deny = false, loop = false;
  String? redirectControl;
  int bodies = 0;
  int bodyBytes = 0;
  List<int> originalBytes = _original, replacementBytes = _replacement;
  String bodyControl = 'max-age=60';
  final requests = <({String path, String? validator})>[];
  void expire() => now = now.add(const Duration(minutes: 6));

  Future<void> _respond(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final validator = request.headers.value(HttpHeaders.ifNoneMatchHeader);
      requests.add((path: path, validator: validator));
      final response = request.response;
      if (deny) {
        response.statusCode = HttpStatus.forbidden;
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      } else if (path == '/image' && (redirect || loop)) {
        response.statusCode = HttpStatus.found;
        response.headers.set(
          HttpHeaders.locationHeader,
          loop ? '/image' : '/other',
        );
        if (redirectControl != null) {
          response.headers.set(
            HttpHeaders.cacheControlHeader,
            redirectControl!,
          );
        }
      } else {
        response.headers.set(HttpHeaders.etagHeader, _tag);
        response.headers.set(HttpHeaders.cacheControlHeader, bodyControl);
        if (validator == _tag) {
          response.statusCode = HttpStatus.notModified;
        } else {
          response.statusCode = HttpStatus.ok;
          final bytes = path == '/other' ? replacementBytes : originalBytes;
          response.add(bytes);
          bodies++;
          bodyBytes += bytes.length;
        }
      }
      await response.close();
    } on SocketException {
      // A client may deliberately abort a header-only rejection/redirect.
    } on HttpException {
      // The loader owns cancellation; no external server participates here.
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final access in ['load', 'cached']) {
    test(
      'recent $access image avoids another body at the 64 entry boundary',
      () async {
        final fixture = await _HttpFixture.start();
        fixture.originalBytes = base64Decode(photo.split(',').last);
        final first = await fixture.loader.load(_source);
        expect(first, isNotNull);
        for (var index = 0; index < 63; index++) {
          expect(
            await fixture.loader.load('https://media.example.test/cold-$index'),
            isNotNull,
          );
        }
        final used = access == 'load'
            ? await fixture.loader.load(_source)
            : fixture.loader.cached(_source);
        expect(identical(used, first), isTrue);
        expect(
          await fixture.loader.load('https://media.example.test/overflow'),
          isNotNull,
        );
        final beforeRequests = fixture.requests.length,
            beforeBytes = fixture.bodyBytes;
        final returned = await fixture.loader.load(_source);
        expect(
          {
            'extraRequests': fixture.requests.length - beforeRequests,
            'extraBodyBytes': fixture.bodyBytes - beforeBytes,
          },
          {'extraRequests': 0, 'extraBodyBytes': 0},
        );
        expect(identical(returned, first), isTrue);
        expect(
          fixture.loader.cached('https://media.example.test/cold-0'),
          isNull,
        );
        fixture.expire();
        final validationBytes = fixture.bodyBytes,
            validationRequests = fixture.requests.length;
        expect(await fixture.loader.load(_source), isNotNull);
        expect(fixture.requests.length - validationRequests, 1);
        expect(fixture.requests.last.validator, _tag);
        expect(fixture.bodyBytes - validationBytes, 0);
      },
    );
  }
  test(
    'recent image avoids another 4MiB body while retaining the 16MiB budget',
    () async {
      final fixture = await _HttpFixture.start();
      const size = 4 * 1024 * 1024;
      fixture.originalBytes = Uint8List(size)
        ..setAll(0, base64Decode(photo.split(',').last));
      final first = await fixture.loader.load(_source);
      expect(first, hasLength(size));
      final cold = [
        for (var index = 0; index < 3; index++)
          'https://media.example.test/large-$index',
      ];
      for (final source in cold) {
        expect(await fixture.loader.load(source), hasLength(size));
      }
      expect(identical(fixture.loader.cached(_source), first), isTrue);
      const overflow = 'https://media.example.test/large-overflow';
      expect(await fixture.loader.load(overflow), hasLength(size));
      final beforeRequests = fixture.requests.length,
          beforeBytes = fixture.bodyBytes;
      final returned = await fixture.loader.load(_source);
      expect(
        {
          'extraRequests': fixture.requests.length - beforeRequests,
          'extraBodyBytes': fixture.bodyBytes - beforeBytes,
        },
        {'extraRequests': 0, 'extraBodyBytes': 0},
      );
      expect(identical(returned, first), isTrue);
      expect(fixture.loader.cached(cold.first), isNull);
      final retained = [_source, ...cold, overflow]
          .map((source) => fixture.loader.cached(source))
          .whereType<Uint8List>()
          .fold<int>(0, (total, bytes) => total + bytes.length);
      expect(retained, 16 * 1024 * 1024);
    },
  );
  for (final control in ['no-store', 'no-cache']) {
    test(
      'menu thumbnail cannot override $control from its raw image',
      () async {
        final fixture = await _HttpFixture.start();
        fixture.originalBytes = base64Decode(photo.split(',').last);
        fixture.bodyControl = control;
        final images = MenuProfileImages(
          now: () => fixture.now,
          remoteImages: fixture.loader,
        );
        addTearDown(images.dispose);
        expect(
          await images.load(_source),
          startsWith('data:image/png;base64,'),
        );
        expect(images.cached(_source), isNull);
        expect(
          await images.load(_source),
          startsWith('data:image/png;base64,'),
        );
        expect(fixture.requests, hasLength(2));
        expect(fixture.bodies, control == 'no-store' ? 2 : 1);
      },
    );
  }
  test('hard image denial also withdraws the derived menu PNG', () async {
    final fixture = await _HttpFixture.start();
    fixture.originalBytes = base64Decode(photo.split(',').last);
    final images = MenuProfileImages(
      now: () => fixture.now,
      remoteImages: fixture.loader,
    );
    addTearDown(images.dispose);
    expect(await images.load(_source), startsWith('data:image/png;base64,'));
    expect(images.cached(_source), isNotNull);
    fixture.expire();
    fixture.deny = true;
    expect(await images.load(_source), isNull);
    expect(images.cached(_source), isNull);
  });
  test('raw owner clear also retires the derived menu cache', () async {
    final fixture = await _HttpFixture.start();
    fixture.originalBytes = base64Decode(photo.split(',').last);
    final images = MenuProfileImages(
      now: () => fixture.now,
      remoteImages: fixture.loader,
    );
    addTearDown(images.dispose);
    expect(await images.load(_source), startsWith('data:image/png;base64,'));
    fixture.loader.clear();
    expect(images.cached(_source), isNull);
  });
  test(
    'validated304 reuses the existing derived PNG without decoding again',
    () async {
      final fixture = await _HttpFixture.start();
      fixture.originalBytes = base64Decode(photo.split(',').last);
      var decodes = 0;
      final images = MenuProfileImages(
        now: () => fixture.now,
        remoteImages: fixture.loader,
        decoder: (bytes, size) {
          decodes++;
          return decodeCommunityImage(bytes, size);
        },
      );
      addTearDown(images.dispose);
      final first = await images.load(_source);
      expect(first, startsWith('data:image/png;base64,'));
      fixture.expire();
      expect(await images.load(_source), first);
      expect(fixture.bodies, 1);
      expect(decodes, 1);
    },
  );
  test(
    'raw owner retirement during decoding cannot publish a late PNG',
    () async {
      final fixture = await _HttpFixture.start();
      final bytes = base64Decode(photo.split(',').last);
      fixture.originalBytes = bytes;
      final ready = Completer<void>();
      final pending = Completer<ui.Image>();
      final prepared = await decodeCommunityImage(bytes, 64);
      final images = MenuProfileImages(
        now: () => fixture.now,
        remoteImages: fixture.loader,
        decoder: (_, _) {
          ready.complete();
          return pending.future;
        },
      );
      addTearDown(images.dispose);
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(prepared);
      });
      final loading = images.load(_source);
      await ready.future;
      fixture.loader.clear();
      pending.complete(prepared);
      expect(await loading, isNull);
      expect(images.cached(_source), isNull);
    },
  );
  test(
    'real HTTP conditional GET avoids a second unchanged response body',
    () async {
      final fixture = await _HttpFixture.start();
      expect(await fixture.loader.load(_source), _original);
      fixture.expire();
      expect(await fixture.loader.load(_source), _original);
      expect(fixture.requests, hasLength(2));
      expect(fixture.requests.last.validator, _tag);
      expect(fixture.bodies, 1);
    },
  );
  test('redirect target change cannot validate a different resource with the same tag', () async {
    final fixture = await _HttpFixture.start();
    expect(await fixture.loader.load(_source), _original);
    fixture.redirect = true;
    fixture.expire();
    expect(await fixture.loader.load(_source), _replacement);
    fixture.expire();
    expect(await fixture.loader.load(_source), _replacement);
    expect(fixture.bodies, 2);
    final targets = fixture.requests.where(
      (request) => request.path == '/other',
    );
    expect(targets, hasLength(2));
    expect(targets.first.validator, isNull);
    expect(targets.last.validator, _tag);
    final aliases = fixture.requests.where(
      (request) => request.path == '/image',
    );
    expect(aliases.last.validator, isNull);
  });
  test(
    'real HTTP no-store denial withdraws bytes and permits an immediate reread',
    () async {
      final fixture = await _HttpFixture.start();
      expect(await fixture.loader.load(_source), _original);
      fixture.deny = true;
      fixture.expire();
      expect(await fixture.loader.load(_source), isNull);
      expect(fixture.loader.cached(_source), isNull);
      fixture.deny = false;
      expect(await fixture.loader.load(_source), _original);
      expect(fixture.requests.last.validator, isNull);
    },
  );
  test(
    'a no-store redirect cannot be hidden by the final response policy',
    () async {
      final fixture = await _HttpFixture.start();
      fixture.redirect = true;
      fixture.redirectControl = 'no-store';
      expect(await fixture.loader.load(_source), _replacement);
      expect(fixture.loader.cached(_source), isNull);
      expect(await fixture.loader.load(_source), _replacement);
      expect(fixture.bodies, 2);
    },
  );
  test(
    'redirect freshness cannot exceed the redirect response limit',
    () async {
      final fixture = await _HttpFixture.start();
      fixture.redirect = true;
      fixture.redirectControl = 'max-age=5';
      expect(await fixture.loader.load(_source), _replacement);
      fixture.now = fixture.now.add(const Duration(seconds: 6));
      expect(await fixture.loader.load(_source), _replacement);
      expect(fixture.requests, hasLength(4));
      expect(fixture.bodies, 1);
    },
  );
  test('redirect loops remain bounded', () async {
    final fixture = await _HttpFixture.start();
    fixture.loop = true;
    expect(await fixture.loader.load(_source), isNull);
    expect(fixture.requests.length, lessThanOrEqualTo(6));
  });
}
