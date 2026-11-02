// After a Host restart every cache is empty and a page asks for many images at
// once. An image that loses that burst must not stay a placeholder for good.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';
import 'package:starbridge_flutter/shared/remote_image_rereads.dart';

final class _Mode extends ChangeNotifier implements ConnectionModeControl {
  @override
  bool busy = false;
  @override
  bool failed = false;
  @override
  ConnectionModeSnapshot get snapshot => const ConnectionModeSnapshot();
  @override
  bool get allowsOnlineTraffic => true;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

/// Each transfer either hangs until the client is closed, or fails at once.
final class _Client extends Fake implements HttpClient {
  _Client(this.hang, this.started);
  final bool hang;
  final List<String> started;
  final _open = <Completer<HttpClientRequest>>[];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    started.add(url.path);
    if (!hang) return Future.error(const SocketException('Synthetic failure'));
    final open = Completer<HttpClientRequest>();
    _open.add(open);
    return open.future;
  }

  @override
  void close({bool force = false}) {
    for (final open in _open) {
      if (!open.isCompleted) {
        open.completeError(const SocketException('Closed'));
      }
    }
    _open.clear();
  }
}

String _source(int id) => 'https://cdn.example.test/static/images/$id.jpg';

void main() {
  testWidgets('a failed image is read again a few times, then left alone', (
    tester,
  ) async {
    final started = <String>[];
    final mode = _Mode();
    var now = DateTime(2026, 10, 30);
    final loader = RemoteImageLoader(
      mode: mode,
      now: () => now,
      createClient: () => _Client(false, started),
    );
    Future<void> wait(int seconds) async {
      now = now.add(Duration(seconds: seconds));
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }

    await tester.pumpWidget(
      RemoteImageScope(
        loader: loader,
        child: RemoteImage(_source(1), width: 10, height: 10),
      ),
    );
    await tester.pump();
    expect(started, hasLength(1));

    await wait(11);
    expect(started, hasLength(2), reason: 'First reread, after the entry expires');
    await wait(30);
    expect(started, hasLength(3));
    await wait(60);
    expect(started, hasLength(4));
    await wait(600);
    expect(started, hasLength(4), reason: 'The rereads are bounded');

    await tester.pumpWidget(const SizedBox());
    loader.dispose();
    await tester.pump(const Duration(seconds: 1));
    mode.dispose();
  });

  testWidgets('only images that failed are told to read again', (tester) async {
    var now = DateTime(2026, 10, 30);
    final rereads = RemoteImageRereads<String>(() => now);
    final told = <String>[];
    void listener() {
      for (final key in const ['failed', 'refused', 'fine']) {
        if (rereads.isDue(key)) told.add(key);
      }
    }

    rereads.addListener(listener);
    rereads.failed('failed');
    rereads.failed('fine');
    rereads.succeeded('fine');
    now = now.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    expect(told, ['failed'], reason: 'A refused image never reports a failure');
    expect(rereads.isDue('failed'), isFalse, reason: 'Only during the notice');

    told.clear();
    rereads.failed('failed');
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(told, ['failed']);
    told.clear();
    rereads.failed('failed');
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 60));
    expect(told, ['failed']);
    told.clear();
    rereads.failed('failed');
    rereads.failed('fine');
    rereads.succeeded('fine');
    now = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 10));
    expect(told, isEmpty, reason: 'Other images succeeding does not restart it');
    rereads.removeListener(listener);
    rereads.reset();
    rereads.dispose();
  });

  testWidgets('no one showing the image means no reread', (tester) async {
    final started = <String>[];
    final mode = _Mode();
    var now = DateTime(2026, 10, 30);
    final loader = RemoteImageLoader(
      mode: mode,
      now: () => now,
      createClient: () => _Client(false, started),
    );
    unawaited(loader.load(_source(1)));
    await tester.pump();
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(started, hasLength(1));
    loader.dispose();
    await tester.pump(const Duration(seconds: 1));
    mode.dispose();
  });
}
