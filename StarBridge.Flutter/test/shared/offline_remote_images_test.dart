import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_images.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';
import 'package:starbridge_flutter/app/composition/remote_image_owner.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:flutter/foundation.dart';

import '../app/menu_overlay/menu_profile_images_test.dart'
    show ImageClient, until;
import '../app/menu_overlay/menu_chat_media_test.dart' show photo;
import '../features/onboarding/bridge_onboarding_adapter_test.dart'
    show wire, checkpoint;
import '../features/onboarding/connection_mode_test.dart' show modeWire;
import '../support/remote_image_fixture.dart';

const imageUrl = 'https://cdn.example.test/avatar.png';
List<int> imageBytes() => base64Decode(photo.split(',').last);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a menu image without a current mode owner cannot start remote HTTP',
    () async {
      final client = ImageClient()
        ..bytes.complete(base64Decode(photo.split(',').last));
      await HttpOverrides.runZoned(() async {
        final images = MenuProfileImages();
        addTearDown(images.dispose);
        expect(
          await images.load('https://cdn.example.test/avatar.png'),
          isNull,
        );
        expect(client.reads, 0);
        expect(await images.load(photo), startsWith('data:image/png;base64,'));
      }, createHttpClient: (_) => client);
    },
  );
  for (final state in ConnectionModeState.values.where(
    (s) => s != ConnectionModeState.online,
  )) {
    test('$state never admits a raw or menu image request', () async {
      final mode = ImageMode()..state = state;
      final client = ImageClient();
      final loader = RemoteImageLoader(mode: mode, createClient: () => client);
      final images = MenuProfileImages(remoteImages: loader);
      expect(await images.load(imageUrl), isNull);
      expect(await loader.load(imageUrl), isNull);
      expect(client.reads, 0);
      images.dispose();
      mode.dispose();
    });
  }
  test('busy or failed positive-looking mode remains denied', () async {
    final mode = ImageMode()..busy = true;
    final client = ImageClient(),
        loader = RemoteImageLoader(mode: mode, createClient: () => client);
    expect(await loader.load(imageUrl), isNull);
    mode.busy = false;
    mode.failed = true;
    mode.notifyListeners();
    expect(await loader.load(imageUrl), isNull);
    expect(client.reads, 0);
    loader.dispose();
    mode.dispose();
  });
  test('offline retains expired bytes, coalesces online reads and revalidates only on resume', () async {
    final mode = ImageMode(),
        client = ImageClient()..bytes.complete(imageBytes());
    var now = DateTime.utc(2026);
    final loader = RemoteImageLoader(
      mode: mode,
      now: () => now,
      createClient: () => client,
    );
    final a = loader.load(imageUrl), b = loader.load(imageUrl);
    expect(identical(a, b), true);
    expect(await a, imageBytes());
    expect(client.reads, 1);
    mode.change(ConnectionModeState.offline);
    now = now.add(const Duration(minutes: 6));
    expect(await loader.load(imageUrl), imageBytes());
    expect(client.reads, 1);
    expect(await loader.load('$imageUrl?new'), isNull);
    expect(client.reads, 1);
    mode.change(ConnectionModeState.online);
    expect(await loader.load(imageUrl), imageBytes());
    expect(client.reads, 2);
    loader.dispose();
    mode.dispose();
  });
  test('pause waits for actual ignored-cancellation exit; late bytes do not enter cache', () async {
    final mode = ImageMode(), client = ImageClient();
    final loader = RemoteImageLoader(mode: mode, createClient: () => client);
    final fetching = loader.load(imageUrl);
    await until(() => client.reads == 1);
    var drained = false;
    final drain = loader.suspendAndDrain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(client.closed, true);
    expect(drained, false);
    expect(await loader.load('$imageUrl?new'), isNull);
    expect(client.reads, 1);
    client.bytes.complete(imageBytes());
    expect(await fetching, isNull);
    await drain;
    expect(drained, true);
    expect(loader.cached(imageUrl), isNull);
    await loader.retireAsync();
    loader.dispose();
    mode.dispose();
  });
  test('window close is independent; root retirement joins a closed child physical exit', () async {
    final mode = ImageMode(), a = ImageClient(), b = ImageClient();
    var created = 0;
    final root = RemoteImageLoader(
      mode: mode,
      createClient: () => created++ == 0 ? a : b,
    );
    final first = root.fork(), second = root.fork();
    final one = first.load(imageUrl), two = second.load(imageUrl);
    await until(() => a.reads == 1 && b.reads == 1);
    first.dispose();
    expect(a.closed, true);
    expect(b.closed, false);
    var done = false;
    final retirement = root.retireAsync().then((_) => done = true);
    expect(b.closed, true);
    await Future<void>.delayed(Duration.zero);
    expect(done, false);
    b.bytes.complete(imageBytes());
    expect(await two, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(done, false);
    a.bytes.complete(imageBytes());
    expect(await one, isNull);
    await retirement;
    expect(done, true);
    root.dispose();
    second.dispose();
    mode.dispose();
  });
  test(
    'owner cache invalidation clears all borrowed windows without fetching',
    () async {
      final mode = ImageMode(),
          client = ImageClient()..bytes.complete(imageBytes());
      final root = RemoteImageLoader(mode: mode, createClient: () => client),
          child = root.fork();
      await child.load(imageUrl);
      expect(child.cached(imageUrl), isNotNull);
      mode.change(ConnectionModeState.offline);
      root.clear();
      expect(child.cached(imageUrl), isNull);
      expect(await child.load(imageUrl), isNull);
      expect(client.reads, 1);
      await root.retireAsync();
      root.dispose();
      child.dispose();
      mode.dispose();
    },
  );
  test('a retired root cannot admit a new window or revive a child on clear notification', () async {
    final mode = ImageMode(),
        client = ImageClient()..bytes.complete(imageBytes());
    final root = RemoteImageLoader(mode: mode, createClient: () => client),
        child = root.fork();
    await child.load(imageUrl);
    child.addListener(() {
      unawaited(child.load('$imageUrl?late'));
    });
    await root.retireAsync();
    final late = root.fork();
    expect(await late.load(imageUrl), isNull);
    expect(client.reads, 1);
    root.dispose();
    child.dispose();
    late.dispose();
    mode.dispose();
  });
  test('original account cache binding preserves offline bytes, then clears on online owner change', () async {
    final mode = ImageMode(),
        client = ImageClient()..bytes.complete(imageBytes());
    final account = ValueNotifier(const AccountProjection.loading());
    final root = RemoteImageLoader(mode: mode, createClient: () => client);
    final binding = RemoteImageOwner(account, root), child = root.fork();
    await child.load(imageUrl);
    expect(child.cached(imageUrl), isNotNull);
    mode.change(ConnectionModeState.offline);
    account.value = account.value.copyWith(
      generation: 8,
      sessionState: AccountSessionState.signedOut,
    );
    expect(child.cached(imageUrl), isNotNull);
    expect(client.reads, 1);
    mode.change(ConnectionModeState.online);
    expect(child.cached(imageUrl), isNull);
    expect(client.reads, 1);
    binding.dispose();
    await root.retireAsync();
    root.dispose();
    child.dispose();
    account.dispose();
    mode.dispose();
  });
  test(
    'suspension waits for original response body exit as well as headers',
    () async {
      final mode = ImageMode(), client = BodyImageClient();
      final loader = RemoteImageLoader(mode: mode, createClient: () => client);
      final fetch = loader.load(imageUrl);
      await until(() => client.listening);
      var done = false;
      final pause = loader.suspendAndDrain().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, false);
      expect(client.closed, true);
      client.body.add(imageBytes());
      await client.body.close();
      expect(await fetch, isNull);
      await pause;
      expect(loader.cached(imageUrl), isNull);
      loader.dispose();
      mode.dispose();
    },
  );
  test('in-flight request count stays bounded, including canceled work awaiting actual exit', () async {
    final mode = ImageMode(), clients = <ImageClient>[];
    final loader = RemoteImageLoader(
      mode: mode,
      createClient: () {
        final client = ImageClient();
        clients.add(client);
        return client;
      },
    );
    var completed = 0;
    final requests = List.generate(
      80,
      (i) => loader.load('$imageUrl?$i').then((value) {
        completed++;
        return value;
      }),
    );
    await until(() => clients.length == 6 && completed == 16);
    expect(clients.fold(0, (count, client) => count + client.reads), 6);
    loader.clear();
    expect(await loader.load('$imageUrl?before-cancel-cleanup'), isNull);
    await until(() => completed == 74);
    final next = loader.load('$imageUrl?next');
    await Future<void>.delayed(Duration.zero);
    expect(
      clients.length,
      6,
      reason: 'Ignored cancellation keeps all six physical slots occupied',
    );
    for (final client in clients.toList()) {
      client.bytes.complete(imageBytes());
    }
    expect(await Future.wait(requests), everyElement(isNull));
    await until(() => clients.length == 7 && clients.last.reads == 1);
    clients.last.bytes.complete(imageBytes());
    expect(await next, imageBytes());
    expect(loader.cached(imageUrl), isNull);
    expect(loader.cached('$imageUrl?next'), imageBytes());
    loader.dispose();
    mode.dispose();
  });
  for (final action in ['manualOffline', 'guideApplyMode']) {
    test(
      '$action same-generation observation invalidation while draining sends no stale write',
      () async {
        final bridge = ImageBridge(),
            mode = ImageMode(),
            client = ImageClient();
        final loader = RemoteImageLoader(
          mode: mode,
          session: bridge.session,
          createClient: () => client,
        );
        final fetch = loader.load(imageUrl);
        await until(() => client.reads == 1);
        final original = BridgeConnectionModeAdapter(bridge.session),
            guide = BridgeOnboardingAdapter(bridge.session);
        final subscription =
            (action == 'manualOffline'
                    ? original.invalidations
                    : guide.invalidations)
                .listen((_) {});
        if (action == 'manualOffline') {
          await original.read();
        } else {
          await guide.read();
        }
        final changed = action == 'manualOffline'
            ? original.enterOffline(4)
            : guide.execute(OnboardingAction.applyMode, checkpoint());
        final failure = expectLater(changed, throwsStateError);
        await until(() => client.closed);
        await bridge.pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'onboarding.changed',
            sessionGeneration: 7,
            sequence: 1,
            payload: const {},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        client.bytes.complete(imageBytes());
        await fetch;
        await failure;
        expect(bridge.writes, isEmpty);
        await subscription.cancel();
        loader.dispose();
        mode.dispose();
        await bridge.close();
      },
    );
  }
  test('overlapping changes cannot reopen image admission before the last original action exits', () async {
    final bridge = ImageBridge(),
        mode = ImageMode(),
        client = ImageClient()..bytes.complete(imageBytes());
    final loader = RemoteImageLoader(
      mode: mode,
      session: bridge.session,
      reconcileMode: () async {},
      createClient: () => client,
    );
    final a = Completer<void>(), b = Completer<void>();
    final one = bridge.session.runConnectionModeChange(() => a.future);
    final two = bridge.session.runConnectionModeChange(() => b.future);
    a.complete();
    await one;
    expect(await loader.load(imageUrl), isNull);
    expect(client.reads, 0);
    b.complete();
    await two;
    expect(await loader.load(imageUrl), imageBytes());
    expect(client.reads, 1);
    loader.dispose();
    mode.dispose();
    await bridge.close();
  });
  for (final action in ['manualOffline', 'guideApplyMode']) {
    test(
      '$action waits for primary, borrowed and already closing image IO before original write',
      () async {
        final bridge = ImageBridge();
        final mode = ConnectionModeController(
          BridgeConnectionModeAdapter(bridge.session),
        );
        await mode.refresh();
        final clients = List.generate(3, (_) => ImageClient());
        var created = 0;
        final root = RemoteImageLoader(
          mode: mode,
          session: bridge.session,
          reconcileMode: mode.refresh,
          createClient: () => clients[created++],
        );
        final child = root.fork(), closing = root.fork();
        final requests = [
          root.load(imageUrl),
          child.load(imageUrl),
          closing.load(imageUrl),
        ];
        await until(() => clients.every((c) => c.reads == 1));
        closing.dispose();
        final guide = BridgeOnboardingAdapter(bridge.session);
        if (action == 'guideApplyMode') await guide.read();
        final Future<Object?> changing = action == 'manualOffline'
            ? mode.enterOffline()
            : guide.execute(OnboardingAction.applyMode, checkpoint());
        await until(() => clients.every((c) => c.closed));
        expect(bridge.writes, isEmpty);
        final newWindow = root.fork();
        expect(await newWindow.load('$imageUrl?new'), isNull);
        expect(created, 3);
        clients[0].bytes.complete(imageBytes());
        clients[1].bytes.complete(imageBytes());
        await Future<void>.delayed(Duration.zero);
        expect(bridge.writes, isEmpty);
        clients[2].bytes.complete(imageBytes());
        await Future.wait(requests);
        await changing;
        await mode.refresh();
        expect(bridge.writes.length, 1);
        expect(bridge.writes.single.accountContext, isNull);
        expect(mode.snapshot.state, ConnectionModeState.offline);
        expect(root.cached(imageUrl), isNull);
        expect(child.cached(imageUrl), isNull);
        expect(await newWindow.load(imageUrl), isNull);
        bridge.state = 'online';
        await mode.refresh();
        // Reconciliation included the window created while admission was paused.
        expect(newWindow.online, true);
        await root.retireAsync();
        root.dispose();
        child.dispose();
        newWindow.dispose();
        mode.dispose();
        await bridge.close();
      },
    );
  }
  test('original generation drift while draining never retags the original mode command', () async {
    final bridge = ImageBridge(), mode = ImageMode();
    final client = ImageClient(),
        loader = RemoteImageLoader(
          mode: mode,
          session: bridge.session,
          createClient: () => client,
        );
    final fetching = loader.load(imageUrl);
    await until(() => client.reads == 1);
    final original = BridgeConnectionModeAdapter(bridge.session);
    await original.read();
    final changing = expectLater(
      original.enterOffline(4),
      throwsA(isA<BridgeStaleGenerationException>()),
    );
    await until(() => client.closed);
    await bridge.pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 8,
        sequence: 1,
        payload: const {},
      ),
    );
    await until(() => bridge.session.activeGeneration == 8);
    client.bytes.complete(imageBytes());
    await fetching;
    await changing;
    expect(bridge.writes, isEmpty);
    expect(await loader.load(imageUrl), isNull);
    loader.dispose();
    mode.dispose();
    await bridge.close();
  });
  test('bridge closure cancels and drains image IO before closing its own connection', () async {
    final bridge = ImageBridge(), mode = ImageMode(), client = ImageClient();
    final loader = RemoteImageLoader(
      mode: mode,
      session: bridge.session,
      createClient: () => client,
    );
    final fetch = loader.load(imageUrl);
    await until(() => client.reads == 1);
    var done = false;
    final close = bridge.session.close().then((_) => done = true);
    var duplicateDone = false;
    final duplicate = bridge.session.close().then((_) => duplicateDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(client.closed, true);
    expect(done, false);
    expect(duplicateDone, false);
    expect(await loader.load('$imageUrl?new'), isNull);
    client.bytes.complete(imageBytes());
    expect(await fetch, isNull);
    await close;
    await duplicate;
    loader.dispose();
    mode.dispose();
    await bridge.close();
  });
  test('a window created after original Bridge closure fails closed without throwing', () async {
    final bridge = ImageBridge(), mode = ImageMode(), client = ImageClient();
    final root = RemoteImageLoader(
      mode: mode,
      session: bridge.session,
      createClient: () => client,
    );
    await bridge.session.close();
    final child = root.fork();
    expect(await child.load(imageUrl), isNull);
    expect(client.reads, 0);
    await root.retireAsync();
    root.dispose();
    child.dispose();
    mode.dispose();
    await bridge.close();
  });
  testWidgets(
    'widget has no independent NetworkImage channel and retains offline cached display',
    (tester) async {
      final mode = ImageMode(),
          client = ImageClient()..bytes.complete(imageBytes());
      final loader = RemoteImageLoader(mode: mode, createClient: () => client);
      const fallback = Text('fallback');
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteImage(imageUrl, errorBuilder: (_, _, _) => fallback),
        ),
      );
      expect(find.text('fallback'), findsOneWidget);
      expect(client.reads, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteImageScope(
            loader: loader,
            child: RemoteImage(
              imageUrl,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );
      expect(client.reads, 1);
      mode.change(ConnectionModeState.offline);
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(client.reads, 1);
      loader.clear();
      await tester.pump();
      expect(find.text('fallback'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      loader.dispose();
      mode.dispose();
    },
  );
}

class BodyImageClient implements HttpClient {
  final body = StreamController<List<int>>();
  bool closed = false, listening = false;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async => BodyImageRequest(this);
  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class BodyImageRequest implements HttpClientRequest {
  BodyImageRequest(this.client);
  final BodyImageClient client;
  @override
  Future<HttpClientResponse> close() async => BodyImageResponse(client);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class BodyImageResponse extends Stream<List<int>>
    implements HttpClientResponse {
  BodyImageResponse(this.client);
  final BodyImageClient client;
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
  }) {
    client.listening = true;
    return client.body.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class ImageBridge {
  ImageBridge() {
    session.acceptHostCapabilities([
      BridgeConnectionModeAdapter.capability,
      BridgeOnboardingAdapter.capability,
    ]);
    subscription = pair.host.incoming.listen((request) async {
      Map<String, Object?> payload;
      if (request.name == 'onboarding.mode.read') {
        payload = modeWire(state);
      } else if (request.name == 'onboarding.read') {
        payload = wire();
      } else {
        writes.add(request);
        state = 'offline';
        payload = request.name == 'onboarding.mode.offline'
            ? modeWire(state)
            : wire();
      }
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: payload,
        ),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  late final StreamSubscription<BridgeEnvelope> subscription;
  String state = 'online';
  final writes = <BridgeEnvelope>[];
  Future<void> close() async {
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  }
}
