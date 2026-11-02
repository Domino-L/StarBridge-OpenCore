// Real framed .NET worker, protected Host storage and anonymous loopback HTTP.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/native_remote_image_disk_cache.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';
import 'package:starbridge_flutter/shared/remote_image_disk_cache.dart';

import '../support/remote_image_fixture.dart';

class _RawHttp extends HttpOverrides {}

class _Client extends Fake implements HttpClient {
  _Client(this.base) : inner = _RawHttp().createHttpClient(null) {
    inner.findProxy = (_) => 'DIRECT';
  }
  final Uri base;
  final HttpClient inner;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) =>
      inner.getUrl(base.replace(path: uri.path));
  @override
  void close({bool force = false}) => inner.close(force: force);
}

class _Worker implements BridgeConnection {
  _Worker(this.process) {
    _stderr = process.stderr.transform(utf8.decoder).join();
    _output = process.stdout.listen(
      _receive,
      onError: controller.addError,
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Worker exited before ready'));
        }
        unawaited(controller.close());
      },
    );
  }
  final Process process;
  final controller = StreamController<BridgeEnvelope>.broadcast(sync: true);
  final ready = Completer<BridgeEnvelope>();
  late final Future<String> _stderr;
  late final StreamSubscription<List<int>> _output;
  var _bytes = <int>[];
  int frames = 0, maximumFrame = 0;
  bool closed = false;
  void _receive(List<int> bytes) {
    _bytes.addAll(bytes);
    while (_bytes.length >= 4) {
      final length = ByteData.sublistView(
        Uint8List.fromList(_bytes),
        0,
        4,
      ).getUint32(0, Endian.little);
      if (length == 0 || length > BridgeProtocol.maximumFrameBytes) {
        controller.addError(StateError('Invalid frame size'));
        return;
      }
      if (_bytes.length < length + 4) return;
      frames++;
      if (length > maximumFrame) maximumFrame = length;
      final envelope = BridgeEnvelope.fromJson(
        (jsonDecode(utf8.decode(_bytes.sublist(4, length + 4))) as Map)
            .cast<String, Object?>(),
      );
      _bytes = _bytes.sublist(length + 4);
      if (envelope.name == 'host.ready' && !ready.isCompleted) {
        ready.complete(envelope);
      } else {
        controller.add(envelope);
      }
    }
  }

  @override
  Stream<BridgeEnvelope> get incoming => controller.stream;
  @override
  Future<void> send(BridgeEnvelope envelope) async {
    final body = utf8.encode(jsonEncode(envelope.toJson()));
    final header = ByteData(4)..setUint32(0, body.length, Endian.little);
    process.stdin
      ..add(header.buffer.asUint8List())
      ..add(body);
    await process.stdin.flush();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await process.stdin.close();
    int code;
    try {
      code = await process.exitCode.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      process.kill();
      code = await process.exitCode;
    }
    await _output.cancel();
    final errors = await _stderr;
    expect(code, 0, reason: errors);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Integration test: three real .NET Host workers. Only the guarded runner
  // supplies the isolated Host assembly; elsewhere it is skipped, not failed.
  final assembly = Platform.environment['STARBRIDGE_IMAGE_WORKER_ASSEMBLY'];
  test('new Native process and loader reuse a fresh protected body; stale body validates with 304', () async {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final shared = Directory(
      '${Directory.systemTemp.path}/StarBridge-image-runtime-$suffix',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final body = Uint8List.fromList(List.generate(4096, (i) => i % 251));
    var requests = 0, bodies = 0, validations = 0, transferredBytes = 0;
    final serving = server.listen((request) async {
      requests++;
      request.response.headers
        ..set(HttpHeaders.cacheControlHeader, 'max-age=300')
        ..set(HttpHeaders.etagHeader, '"unchanged-image"');
      if (request.headers.value(HttpHeaders.ifNoneMatchHeader) ==
          '"unchanged-image"') {
        validations++;
        request.response.statusCode = HttpStatus.notModified;
      } else {
        bodies++;
        transferredBytes += body.length;
        request.response
          ..contentLength = body.length
          ..add(body);
      }
      await request.response.close();
    });
    final workers = <_Worker>[];
    final sessions = <BridgeClientSession>[];
    final loaders = <RemoteImageLoader>[];
    final modes = <ImageMode>[];
    addTearDown(() async {
      for (final loader in loaders) {
        await loader.retireAsync();
        loader.dispose();
      }
      for (final session in sessions) {
        await session.close();
      }
      for (final worker in workers) {
        await worker.close();
      }
      for (final mode in modes) {
        mode.dispose();
      }
      await server.close(force: true);
      await serving.cancel();
      if (await shared.exists()) await shared.delete(recursive: true);
    });
    Future<(RemoteImageLoader, BridgeClientSession, _Worker)> open() async {
      final worker = _Worker(
        await Process.start('dotnet', [
          assembly!,
          '--image-cache-runtime-worker',
          shared.path,
        ]),
      );
      workers.add(worker);
      final ready = await worker.ready.future.timeout(
        const Duration(seconds: 8),
      );
      final session = BridgeClientSession(
        connection: worker,
        sessionGeneration: ready.sessionGeneration,
      );
      session.acceptHostCapabilities(
        (ready.payload['capabilities'] as List).cast<String>(),
      );
      sessions.add(session);
      final mode = ImageMode(scope: ready.sessionGeneration);
      modes.add(mode);
      final loader = RemoteImageLoader(
        mode: mode,
        session: session,
        diskCache: NativeRemoteImageDiskCache(session),
        createClient: () => _Client(base),
      );
      loaders.add(loader);
      return (loader, session, worker);
    }

    const source = 'https://images.example.test/unchanged.png';
    final first = await open();
    expect(
      await first.$1.load(source, kind: RemoteImageResourceKind.ship),
      body,
    );
    expect(
      await first.$1.load(source, kind: RemoteImageResourceKind.ship),
      body,
    );
    expect((requests, bodies, transferredBytes, validations), (1, 1, 4096, 0));
    await first.$1.retireAsync();
    await first.$2.close();
    final second = await open();
    expect(second.$3.process.pid, isNot(first.$3.process.pid));
    expect(
      await second.$1.load(source, kind: RemoteImageResourceKind.ship),
      body,
    );
    expect(
      (requests, bodies, transferredBytes, validations),
      (1, 1, 4096, 0),
      reason:
          'Host process replacement must not download or validate a fresh body',
    );
    // The exact 4 MiB product limit traverses both real codecs in bounded
    // chunks, then survives another independent Host process replacement.
    const fullSource = 'https://images.example.test/full.png';
    final full = Uint8List.fromList(
      List.generate(4 * 1024 * 1024, (i) => i % 251),
    );
    final fullLease = await NativeRemoteImageDiskCache(second.$2).open(
      fullSource,
      maxBytes: full.length,
      followRedirects: true,
      kind: RemoteImageResourceKind.ship,
    );
    expect(fullLease, isNotNull);
    final stored = DateTime.now().toUtc();
    await fullLease!.store(
      RemoteImageDiskSnapshot(
        bytes: full,
        storedAt: stored,
        freshUntil: stored.add(const Duration(seconds: 300)),
        maxAgeSeconds: 300,
        noCache: false,
        mustRevalidate: false,
      ),
    );
    // Age only the controlled local fixture metadata. Both production clocks
    // remain real; the next process must perform an actual conditional GET.
    final aging = await NativeRemoteImageDiskCache(second.$2).open(
      source,
      maxBytes: 4 * 1024 * 1024,
      followRedirects: true,
      kind: RemoteImageResourceKind.ship,
    );
    final original = aging!.snapshot!;
    final old = DateTime.now().toUtc().subtract(const Duration(minutes: 6));
    await aging.store(
      RemoteImageDiskSnapshot(
        bytes: original.bytes,
        storedAt: old,
        freshUntil: old.add(const Duration(seconds: 300)),
        maxAgeSeconds: 300,
        noCache: false,
        mustRevalidate: false,
        etag: original.etag,
        validatorTarget: original.validatorTarget,
      ),
    );
    await second.$1.retireAsync();
    await second.$2.close();
    final third = await open();
    final fullRead = await NativeRemoteImageDiskCache(third.$2).open(
      fullSource,
      maxBytes: full.length,
      followRedirects: true,
      kind: RemoteImageResourceKind.ship,
    );
    expect(fullRead?.snapshot?.bytes, full);
    await fullRead?.close();
    expect(
      await third.$1.load(source, kind: RemoteImageResourceKind.ship),
      body,
    );
    expect((requests, bodies, transferredBytes, validations), (2, 1, 4096, 1));
    expect(
      workers.every((w) => w.maximumFrame <= BridgeProtocol.maximumFrameBytes),
      isTrue,
    );
  },
    timeout: const Timeout(Duration(seconds: 40)),
    skip: assembly == null
        ? 'Needs the guarded runner to set STARBRIDGE_IMAGE_WORKER_ASSEMBLY (real .NET Host worker)'
        : null,
  );
}
