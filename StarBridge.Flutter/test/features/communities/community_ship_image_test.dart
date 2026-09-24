import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_image_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

final _target = 'a' * 32, _ship = 'b' * 32;
Map<String, Object?> _chunk(Uint8List bytes, int offset) {
  final end = (offset + 192 * 1024).clamp(0, bytes.length);
  return {
    'schemaVersion': 1,
    'targetRef': _target,
    'shipRef': _ship,
    'version': 'c' * 64,
    'contentHash': sha256.convert(bytes).toString(),
    'mimeType': 'image/png',
    'totalBytes': bytes.length,
    'offset': offset,
    'next': end == bytes.length ? null : end,
    'data': base64Encode(bytes.sublist(offset, end)),
    'cropFocusX': .3,
    'cropFocusY': .7,
    'cropZoom': 1.4,
  };
}

class _Port implements CommunityShipImagePort {
  _Port(this.reader);
  final Future<Map<String, Object?>> Function(int, String?) reader;
  @override
  bool get shipImageAvailable => true;
  @override
  Future<Map<String, Object?>> readShipImage(
    String targetRef,
    String shipRef, {
    required int offset,
    String? version,
  }) => reader(offset, version);
}

void main() {
  test('formal bridge requests scoped image and exposes capability', () async {
    final host = CommunityHarness(
      capabilities: ['communities.shipImage'],
      responses: {
        'communities.shipImage': _chunk(Uint8List.fromList([1, 2, 3]), 0),
      },
    );
    addTearDown(host.close);
    expect(host.adapter.shipImageAvailable, isTrue);
    final image = await assembleCommunityShipImage(
      host.adapter,
      _target,
      _ship,
      checkCurrent: () {},
    );
    expect(image.bytes, [1, 2, 3]);
    expect(image.focusX, .3);
    expect(image.focusY, .7);
    expect(image.zoom, 1.4);
    expect(image.version, 'c' * 64);
    final request = host.requests
        .where((r) => r.name == 'communities.shipImage')
        .single;
    expect(request.payload['shipRef'], _ship);
  });
  test(
    'all chunks are bounded and use same version before publishing original',
    () async {
      final bytes = Uint8List(220 * 1024);
      var calls = 0;
      final port = _Port((offset, version) async {
        calls++;
        expect(version, offset == 0 ? null : 'c' * 64);
        return _chunk(bytes, offset);
      });
      final image = await assembleCommunityShipImage(
        port,
        _target,
        _ship,
        checkCurrent: () {},
      );
      expect(calls, 2);
      expect(image.bytes, bytes);
    },
  );
  for (final fault in [
    'target',
    'ship',
    'version',
    'hash',
    'mime',
    'total',
    'count',
    'offset',
    'next',
    'crop',
    'checksum',
  ]) {
    test(
      'reject invalid image $fault without exposing partial bytes',
      () async {
        final bytes = Uint8List(220 * 1024);
        final port = _Port((offset, version) async {
          final row = _chunk(bytes, offset);
          if (offset > 0) {
            switch (fault) {
              case 'target':
                row['targetRef'] = 'f' * 32;
              case 'ship':
                row['shipRef'] = 'f' * 32;
              case 'version':
                row['version'] = 'f' * 64;
              case 'hash':
                row['contentHash'] = 'f' * 64;
              case 'mime':
                row['mimeType'] = 'image/jpeg';
              case 'total':
                row['totalBytes'] = bytes.length + 1;
              case 'count':
                row['data'] = 'AQ==';
              case 'offset':
                row['offset'] = 0;
              case 'next':
                row['next'] = bytes.length;
              case 'crop':
                row['cropZoom'] = 1.5;
              case 'checksum':
                final damaged = base64Decode(row['data']! as String);
                damaged[0] = 1;
                row['data'] = base64Encode(damaged);
            }
          }
          return row;
        });
        await expectLater(
          assembleCommunityShipImage(port, _target, _ship, checkCurrent: () {}),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'identity changes stop between chunks and after the last response',
    () async {
      var valid = true, calls = 0;
      final port = _Port((offset, version) async {
        calls++;
        valid = false;
        return _chunk(Uint8List(220 * 1024), offset);
      });
      await expectLater(
        assembleCommunityShipImage(
          port,
          _target,
          _ship,
          checkCurrent: () {
            if (!valid) throw const CommunityFailure('identityUnavailable');
          },
        ),
        throwsA(isA<CommunityFailure>()),
      );
      expect(calls, 1);
    },
  );
  test('malformed caller reference never reaches bridge', () async {
    final host = CommunityHarness(capabilities: ['communities.shipImage']);
    addTearDown(host.close);
    await expectLater(
      host.adapter.readShipImage(_target, 'not-a-ref', offset: 0),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
}
