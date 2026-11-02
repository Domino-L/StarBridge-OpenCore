// Trader avatars on offers (CX-T18, CX-T19): the Host passes only validated
// RSI addresses; the client loads them through the shared remote-image loader
// over the initials, falls back to the initials, and never follows a redirect
// away from the vetted address.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_components.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart'
    show TradeSheet;
import 'package:starbridge_flutter/shared/remote_image.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';


import '../../support/remote_image_fixture.dart' show ImageMode;
import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_trades_test.dart' show TradesPort;

const _avatar =
    'https://robertsspaceindustries.com/media/abc/heap_infobox/x.png';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _RawHttp extends HttpOverrides {}

/// Sends every URL to a loopback server, as the shared image tests do.
final class _Loopback extends Fake implements HttpClient {
  _Loopback(this.base) : inner = _RawHttp().createHttpClient(null) {
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

/// An in-memory HTTP client: every request answers [status]. No socket is
/// opened; redirects are covered by the loopback test below.
class _Client implements HttpClient {
  _Client(this.status);
  final int status;
  final asked = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    asked.add(uri);
    return _Request(this);
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.client);
  final _Client client;
  @override
  bool followRedirects = true;
  @override
  final HttpHeaders headers = _Headers(null);
  @override
  Future<HttpClientResponse> close() async => _Response(client);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.client) : headers = _Headers(null);
  final _Client client;
  @override
  final HttpHeaders headers;
  List<int> get _body => client.status == 200 ? _png : const [];
  @override
  int get statusCode => client.status;
  @override
  int get contentLength => _body.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers extends Fake implements HttpHeaders {
  _Headers(this.location);
  final String? location;
  @override
  List<String>? operator [](String name) =>
      name.toLowerCase() == HttpHeaders.locationHeader && location != null
      ? [location!]
      : null;
  @override
  String? value(String name) =>
      name.toLowerCase() == HttpHeaders.locationHeader ? location : null;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

Future<_Client> _pump(
  WidgetTester tester,
  _Client client, {
  List<Widget>? children,
}) async {
  final mode = ImageMode();
  final loader = RemoteImageLoader(mode: mode, createClient: () => client);
  addTearDown(() {
    loader.dispose();
    mode.dispose();
  });
  await tester.pumpWidget(
    preview(
      RemoteImageScope(
        loader: loader,
        child: Column(
          children:
              children ?? const [ItemTraderAvatar('a***u', avatar: _avatar)],
        ),
      ),
      AppearanceMode.dark,
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  return client;
}

void main() {
  testWidgets('a loaded avatar covers the initials; one address, one request', (
    tester,
  ) async {
    final client = await _pump(
      tester,
      _Client(200),
      children: const [
        ItemTraderAvatar('a***u', avatar: _avatar),
        ItemTraderAvatar('a***u', avatar: _avatar),
      ],
    );
    expect(find.byType(Image), findsNWidgets(2));
    expect(client.asked, hasLength(1), reason: 'same address shared');
    expect(find.text('AU'), findsNWidgets(2), reason: 'initials underneath');
    expect(tester.takeException(), isNull);
    // Let the loader's failure back-off timer run out inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('a failed avatar leaves the initials', (tester) async {
    await _pump(tester, _Client(404));
    expect(find.byType(Image), findsNothing);
    expect(find.text('AU'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Let the loader's failure back-off timer run out inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('the trader avatar asks the loader not to follow redirects', (
    tester,
  ) async {
    await _pump(tester, _Client(404));
    expect(
      tester.widget<RemoteImage>(find.byType(RemoteImage)).followRedirects,
      isFalse,
    );
    // Let the loader's failure back-off timer run out inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  test(
    'without redirects, a 302 to another host stops at the first hop',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final sub = server.listen((request) async {
        paths.add(request.uri.path);
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'https://elsewhere.example.test/other',
          );
        try {
          await request.response.close();
        } on Object {
          // The loader may abort a header-only redirect.
        }
      });
      final mode = ImageMode();
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final loader = RemoteImageLoader(
        mode: mode,
        createClient: () => _Loopback(base),
      );
      try {
        for (final follow in [false, true]) {
          paths.clear();
          final bytes = await loader.load(
            follow ? '$_avatar?f' : _avatar,
            followRedirects: follow,
            kind: RemoteImageResourceKind.avatar,
          );
          expect(bytes, isNull);
          // The loopback sends every host to this server, so a followed
          // redirect shows up as a second request for /other.
          expect(paths.first, '/media/abc/heap_infobox/x.png');
          if (follow) {
            expect(paths.length, greaterThan(1));
            expect(paths[1], '/other');
          } else {
            expect(paths, hasLength(1));
          }
        }
      } finally {
        await loader.retireAsync();
        loader.dispose();
        mode.dispose();
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );

  testWidgets('the trade sheet avatar loads without redirects, over initials', (
    tester,
  ) async {
    final mode = ImageMode();
    final client = _Client(200);
    final loader = RemoteImageLoader(mode: mode, createClient: () => client);
    addTearDown(() {
      loader.dispose();
      mode.dispose();
    });
    final c = MarketplaceController(TradesPort());
    addTearDown(c.dispose);
    c.trades.detail = {
      ...TradesPort().row,
      'counterpartyName': 'Hawk_07',
      'counterpartyAvatar': _avatar,
    };
    await tester.pumpWidget(
      preview(
        RemoteImageScope(loader: loader, child: TradeSheet(c)),
        AppearanceMode.dark,
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final image = tester.widget<RemoteImage>(
      find.byKey(const ValueKey('market-trade-counterparty-avatar')),
    );
    expect(image.followRedirects, isFalse);
    expect(image.kind, RemoteImageResourceKind.avatar);
    expect(client.asked, hasLength(1));
    expect(find.text('H7'), findsOneWidget, reason: 'initials underneath');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('no address or a non-https one: initials only, no request', (
    tester,
  ) async {
    final client = await _pump(
      tester,
      _Client(200),
      children: const [
        ItemTraderAvatar('D*****8'),
        ItemTraderAvatar('N*****a', avatar: 'http://example.com/a.png'),
      ],
    );
    expect(client.asked, isEmpty);
    expect(find.byType(RemoteImage), findsNothing);
    expect(find.text('D8'), findsOneWidget);
    expect(find.text('NA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Let the loader's failure back-off timer run out inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });
}
