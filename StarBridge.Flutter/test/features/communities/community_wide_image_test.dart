import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

void main() {
  const capabilities = [
    'communities.read',
    'communities.commands',
    'communities.wideImage',
  ];
  Map<String, Object?> selected({String? preview, int width = 1920}) => {
    'schemaVersion': 1,
    'status': 'selected',
    'source': {
      'sourceRef': 'a' * 32,
      'previewImageData': preview ?? 'data:image/png;base64,AQ==',
      'width': width,
      'height': 1080,
    },
  };
  test(
    'wide port requires capability before sending any image request',
    () async {
      final host = CommunityHarness();
      addTearDown(host.close);
      expect(host.adapter.canPickWideImage, isFalse);
      await expectLater(
        host.adapter.pickWideImage('banner'),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        host.adapter.clearWideImage(),
        throwsA(isA<CommunityFailure>()),
      );
      expect(host.requests, isEmpty);
    },
  );
  for (final kind in ['banner', 'background']) {
    test('wide $kind port round trip and exact payload', () async {
      final image =
          'data:image/jpeg;base64,${base64Encode(Uint8List(2 * 1024 * 1024))}';
      final host = CommunityHarness(
        capabilities: capabilities,
        responses: {
          'communities.pickWideImage': selected(),
          'communities.cropWideImage': {
            'schemaVersion': 1,
            'status': 'cropped',
            'imageData': image,
          },
          'communities.clearWideImage': {
            'schemaVersion': 1,
            'status': 'cleared',
          },
        },
      );
      addTearDown(host.close);
      expect(host.adapter.canPickWideImage, isTrue);
      final source = await host.adapter.pickWideImage(kind);
      expect(source!.width, 1920);
      expect(source.height, 1080);
      expect(source.sourceRef, 'a' * 32);
      expect(
        await host.adapter.cropWideImage(source.sourceRef, kind, .1, .2, .5),
        image,
      );
      await host.adapter.clearWideImage();
      expect(
        host.requests
            .firstWhere((r) => r.name == 'communities.pickWideImage')
            .payload,
        {'schemaVersion': 1, 'kind': kind},
      );
      expect(
        host.requests
            .firstWhere((r) => r.name == 'communities.cropWideImage')
            .payload,
        {
          'schemaVersion': 1,
          'sourceRef': 'a' * 32,
          'kind': kind,
          'x': .1,
          'y': .2,
          'width': .5,
        },
      );
      await host.adapter.close();
      expect(host.adapter.canPickWideImage, isFalse);
    });
  }
  test('picker cancellation returns null', () async {
    final host = CommunityHarness(
      capabilities: capabilities,
      responses: {
        'communities.pickWideImage': {
          'schemaVersion': 1,
          'status': 'cancelled',
        },
      },
    );
    addTearDown(host.close);
    expect(await host.adapter.pickWideImage('banner'), isNull);
  });
  testWidgets('native picker survives ordinary bridge timeout', (tester) async {
    final host = CommunityHarness(
      capabilities: capabilities,
      holdNames: {'communities.pickWideImage'},
      responses: {'communities.pickWideImage': selected()},
    );
    addTearDown(host.close);
    var finished = false;
    final picking = host.adapter.pickWideImage('banner').then((source) {
      finished = true;
      return source;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(finished, isFalse);
    await host.reply(
      host.requests.firstWhere((r) => r.name == 'communities.pickWideImage'),
    );
    await tester.pump();
    expect((await picking)!.sourceRef, 'a' * 32);
  });
  for (final response in [
    selected(preview: 'x' * 700001),
    selected(width: 0),
    selected(width: 16777217),
    selected(preview: 'data:image/png;base64,???'),
    {'schemaVersion': 1, 'status': 'cropped'},
  ]) {
    test('malformed selected preview rejected ${response.hashCode}', () async {
      final host = CommunityHarness(
        capabilities: capabilities,
        responses: {'communities.pickWideImage': response},
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.pickWideImage('background'),
        throwsFormatException,
      );
    });
  }
  for (final data in [
    'data:image/png;base64,AQ==',
    'data:image/jpeg;base64,???',
    'data:image/jpeg;base64,${base64Encode(Uint8List(2 * 1024 * 1024 + 1))}',
  ]) {
    test('malformed cropped bytes rejected ${data.length}', () async {
      final host = CommunityHarness(
        capabilities: capabilities,
        responses: {
          'communities.cropWideImage': {
            'schemaVersion': 1,
            'status': 'cropped',
            'imageData': data,
          },
        },
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.cropWideImage('a' * 32, 'banner', 0, 0, 1),
        throwsFormatException,
      );
    });
  }
  test('invalid crop inputs fail locally', () async {
    final host = CommunityHarness(capabilities: capabilities);
    addTearDown(host.close);
    for (final (kind, x, y, width) in [
      ('square', 0.0, 0.0, 1.0),
      ('banner', .9, 0.0, .2),
      ('banner', 0.0, 0.0, .19),
      ('banner', double.nan, 0.0, .5),
    ]) {
      await expectLater(
        host.adapter.cropWideImage('a' * 32, kind, x, y, width),
        throwsFormatException,
      );
    }
    expect(host.requests, isEmpty);
  });

  BridgeEnvelope frame(String name, String type, int bytes) => BridgeEnvelope(
    protocolVersion: 1,
    messageType: type,
    name: name,
    correlationId: 'synthetic',
    sessionGeneration: 1,
    status: type == 'response' ? 'ok' : null,
    sequence: type == 'event' ? 1 : null,
    payload: {'imageData': 'a' * bytes},
  );
  Uint8List raw(BridgeEnvelope envelope) {
    final payload = utf8.encode(jsonEncode(envelope.toJson()));
    final bytes = Uint8List(payload.length + 4);
    ByteData.sublistView(bytes).setUint32(0, payload.length, Endian.little);
    bytes.setRange(4, bytes.length, payload);
    return bytes;
  }

  test(
    'crop response permits 2 MiB base64 while save request retains 8 MiB',
    () {
      for (final envelope in [
        frame('communities.cropWideImage', 'response', 2796236),
        frame('communities.saveProfile', 'request', 6 * 1024 * 1024),
      ]) {
        final decoded = BridgeFrameCodec.decode(
          BridgeFrameCodec.encode(envelope),
        );
        expect(decoded.payload, envelope.payload);
      }
    },
  );
  test(
    'frame exception is scoped to crop response name, direction and 4 MiB',
    () {
      for (final envelope in [
        frame('communities.cropWideImage', 'request', 2 * 1024 * 1024),
        frame('communities.cropWideImage', 'event', 2 * 1024 * 1024),
        frame('communities.pickWideImage', 'response', 2 * 1024 * 1024),
        frame('communities.saveProfile', 'response', 2 * 1024 * 1024),
        frame('communities.cropWideImage', 'response', 4 * 1024 * 1024),
      ]) {
        expect(
          () => BridgeFrameCodec.encode(envelope),
          throwsA(isA<BridgeFormatException>()),
        );
        expect(
          () => BridgeFrameCodec.decode(raw(envelope)),
          throwsA(isA<BridgeFormatException>()),
        );
      }
    },
  );
}
