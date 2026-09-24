import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profiles_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_images.dart';
import 'package:starbridge_flutter/platform/window/menu_profile_navigation.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';

import 'menu_profiles_session_test.dart' show ProfilePort, fixtureProfile;
import 'menu_chat_media_test.dart' show photo;

class ImageClient implements HttpClient {
  int reads = 0;
  bool closed = false;
  int status = 200;
  int? declaredLength;
  final bytes = Completer<List<int>>();
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    reads++;
    return ImageRequest(bytes.future, status, declaredLength);
  }

  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class ImageRequest implements HttpClientRequest {
  ImageRequest(this.bytes, this.status, this.declaredLength);
  final Future<List<int>> bytes;
  final int status;
  final int? declaredLength;
  @override
  Future<HttpClientResponse> close() async =>
      ImageResponse(await bytes, status, declaredLength);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  ImageResponse(this.bytes, this.status, this.declaredLength);
  final List<int> bytes;
  final int status;
  final int? declaredLength;
  @override
  int get statusCode => status;
  @override
  int get contentLength => declaredLength ?? bytes.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('directory-sized inline logo survives profile parsing and menu thumbnail projection', () async {
    final bytes = Uint8List(512 * 1024);
    final png = base64Decode(photo.split(',').last);
    bytes.setRange(0, png.length, png);
    final source = 'data:image/png;base64,${base64Encode(bytes)}';
    final snapshot = parsePersonalProfileSnapshot({
      'schemaVersion': 1,
      'editable': false,
      'profile': {
        'isPublic': true,
        'identity': {'callSign': 'Fixture', 'gameHandle': 'Fixture-Pilot'},
        'content': <String, Object?>{},
        'fleetAffiliation': {
          'fleetName': 'Fixture organization',
          'fleetCode': 'TEST',
          'kind': 'community',
          'logoImageData': source,
        },
      },
    });
    final views = <Map<String, Object?>>[];
    final session = MenuProfilesSession(() {
      final port = ProfilePort()..pending.complete(snapshot);
      return port;
    }, views.add);
    addTearDown(session.dispose);
    session.open(
      'large-logo',
      MenuProfileTarget(
        source: 'friend',
        reference: 'fixture',
        query: '',
        isCurrent: () => true,
        isAccountCurrent: () => true,
      ),
    );
    await until(
      () =>
          views.isNotEmpty &&
          MenuProfileView.parse(views.last)
                  .snapshot
                  ?.affiliations
                  .single
                  .logoImageData !=
              null,
    );
    final image = MenuProfileView.parse(views.last)
        .snapshot!
        .affiliations
        .single
        .logoImageData!;
    expect(
      base64Decode(image.split(',').last).length,
      lessThanOrEqualTo(20000),
    );
    expect(jsonEncode(views), isNot(contains(source)));
  });
  test(
    'cache coalesces requests, retries failures and expires successful images',
    () async {
      final client = ImageClient()..status = 500;
      var now = DateTime.utc(2026);
      await HttpOverrides.runZoned(() async {
        final images = MenuProfileImages(now: () => now);
        addTearDown(images.dispose);
        const url = 'https://cdn.example.test/logo.png';
        final first = images.load(url), duplicate = images.load(url);
        expect(identical(first, duplicate), true);
        client.bytes.complete(base64Decode(photo.split(',').last));
        expect(await first, isNull);
        expect(client.reads, 1);
        expect(await images.load(url), isNull);
        expect(client.reads, 1);
        client.status = 200;
        now = now.add(const Duration(seconds: 11));
        expect(await images.load(url), startsWith('data:image/png;base64,'));
        expect(client.reads, 2);
        expect(await images.load(url), isNotNull);
        expect(client.reads, 2);
        now = now.add(const Duration(minutes: 6));
        expect(
          images.cached(url),
          isNotNull,
          reason: 'expiry must not clear an already displayed thumbnail',
        );
        expect(await images.load(url), isNotNull);
        expect(client.reads, 3);
        images.dispose();
        expect(client.closed, true);
        expect(images.cached(url), isNull);
        expect(await images.load(url), isNull);
      }, createHttpClient: (_) => client);
    },
  );
  test('invalid or local sources are never downloaded', () async {
    final client = ImageClient();
    await HttpOverrides.runZoned(() async {
      final images = MenuProfileImages();
      addTearDown(images.dispose);
      for (final source in [
        'http://cdn.example.test/logo',
        'file:///secret',
        'https://localhost/logo',
        'https://127.0.0.1/logo',
        Uri(scheme: 'https', host: '192.168.1.1', path: '/logo').toString(),
        'https://[::1]/logo',
        'https://user:password@example.com/logo',
        'https://cdn.example.test:4433/logo',
      ]) {
        expect(await images.load(source), isNull);
      }
      expect(client.reads, 0);
      expect(await images.load(photo), startsWith('data:image/png;base64,'));
      expect(client.reads, 0);
    }, createHttpClient: (_) => client);
  });
  for (final mode in ['redirect', 'declared-size', 'stream-size', 'corrupt']) {
    test('rejects $mode image responses', () async {
      final client = ImageClient()
        ..status = mode == 'redirect' ? 302 : 200
        ..declaredLength = mode == 'declared-size' ? 600000 : -1;
      client.bytes.complete(
        mode == 'stream-size' ? List.filled(600000, 0) : [0, 1, 2],
      );
      await HttpOverrides.runZoned(() async {
        final images = MenuProfileImages();
        addTearDown(images.dispose);
        expect(await images.load('https://cdn.example.test/logo.png'), isNull);
      }, createHttpClient: (_) => client);
    });
  }
  for (final action in ['close', 'identity', 'refresh-denied']) {
    test('late image never revives a profile after $action', () async {
      final client = ImageClient();
      await HttpOverrides.runZoned(() async {
        final views = <Map<String, Object?>>[], ports = <ProfilePort>[];
        final session = MenuProfilesSession(() {
          final p = ProfilePort();
          ports.add(p);
          p.pending.complete(
            ports.length == 1
                ? fixtureProfile
                : const PersonalProfileSnapshot.unavailable(
                    failureKey: 'profile.visitor.notVisible',
                  ),
          );
          return p;
        }, views.add);
        addTearDown(session.dispose);
        session.open(
          'p1',
          MenuProfileTarget(
            source: 'friend',
            reference: 'private',
            query: '',
            isCurrent: () => true,
            isAccountCurrent: () => true,
          ),
        );
        await until(() => client.reads == 1);
        if (action == 'close') {
          session.closeWindow('p1');
        } else if (action == 'identity') {
          ports.first.changes.add(null);
          await until(() => views.last['state'] == 'revoked');
        } else {
          session.refresh('p1');
          await until(() => views.last['state'] == 'notVisible');
        }
        final count = views.length;
        client.bytes.complete(base64Decode(photo.split(',').last));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(views.length, count);
        expect(client.closed, true);
      }, createHttpClient: (_) => client);
    });
  }
  test('URL-only organization logo loads after text and stays inline on the menu wire', () async {
    final client = ImageClient();
    await HttpOverrides.runZoned(() async {
      final views = <Map<String, Object?>>[], ports = <ProfilePort>[];
      final session = MenuProfilesSession(() {
        final p = ProfilePort();
        ports.add(p);
        p.pending.complete(fixtureProfile);
        return p;
      }, views.add);
      addTearDown(session.dispose);
      session.open(
        'p1',
        MenuProfileTarget(
          source: 'friend',
          reference: 'private',
          query: '',
          isCurrent: () => true,
          isAccountCurrent: () => true,
        ),
      );
      await until(() => views.isNotEmpty && views.last['state'] == 'ready');
      expect(
        MenuProfileView.parse(views.last).snapshot!.callSign,
        fixtureProfile.callSign,
      );
      client.bytes.complete(base64Decode(photo.split(',').last));
      await until(
        () =>
            MenuProfileView.parse(views.last)
                .snapshot
                ?.affiliations
                .single
                .logoImageData !=
            null,
      );
      expect(client.reads, 1);
      expect(jsonEncode(views), isNot(contains('https://')));
      expect(jsonEncode(views), isNot(contains('private-image')));
      session.refresh('p1');
      await until(() => ports.length == 2 && views.last['state'] == 'ready');
      expect(
        MenuProfileView.parse(views.last)
            .snapshot!
            .affiliations
            .single
            .logoImageData,
        isNotNull,
      );
      expect(client.reads, 1);
      session.dispose();
    }, createHttpClient: (_) => client);
  });
}
