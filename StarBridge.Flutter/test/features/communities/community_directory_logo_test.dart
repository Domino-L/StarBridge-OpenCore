import 'community_image_test_support.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

final original = Uint8List(150000)
  ..setAll(
    0,
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=',
    ),
  );
final directory = <String, Object?>{
  'schemaVersion': 1,
  'view': 'discover',
  'query': '',
  'totalCount': 17,
  'next': null,
  'items': List.generate(
    17,
    (i) => {
      'targetRef': i.toRadixString(16).padLeft(32, '0'),
      'name': 'Organization $i',
      'description': '',
      'language': '',
      'activeTime': '',
      'memberCount': 1,
      'relationship': 'none',
      'joinMode': 'application',
      'actions': <String>[],
      'logoDeferred': true,
    },
  ),
};
final media = <String, Object?>{
  'schemaVersion': 1,
  'kind': 'logo',
  'memberRef': null,
  'version': sha256.convert(original).toString(),
  'mimeType': 'image/png',
  'totalBytes': original.length,
  'offset': 0,
  'next': null,
  'data': base64Encode(original),
};

void main() {
  testWidgets('unchanged sidebar logo reuses decoded bytes on parent rebuild', (
    tester,
  ) async {
    final data = 'data:image/png;base64,${base64Encode(original)}';
    Widget scene(double size) => MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('en'),
      ),
      home: CommunityLogo(data: data, size: size),
    );
    await tester.pumpWidget(scene(40));
    final first = tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    await tester.pumpWidget(scene(42));
    final second =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(
      (second.imageProvider as MemoryImage).bytes,
      same((first.imageProvider as MemoryImage).bytes),
    );
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'Account change cancels deferred logos and rejects the old page',
    () async {
      final host = CommunityHarness(
        legacy: true,
        capabilities: ['communities.read', 'communities.media'],
        holdNames: {'communities.media'},
        responses: {'communities.read': directory},
      );
      addTearDown(host.close);
      final reading = host.adapter.read(view: 'discover', query: '');
      final rejected = expectLater(reading, throwsA(isA<CommunityFailure>()));
      for (
        var i = 0;
        i < 100 && !host.requests.any((r) => r.name == 'communities.media');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(host.requests.any((r) => r.name == 'communities.media'), isTrue);
      final invalidated = host.adapter.invalidations.first;
      await host.connection.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 5,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await invalidated;
      await rejected;
      expect(
        host.requests.where((r) => r.name == 'communities.media').length,
        lessThanOrEqualTo(3),
      );
    },
  );
  test(
    '17 recommended cards retain large original logos through media channel',
    () async {
      final host = CommunityHarness(
        legacy: true,
        capabilities: ['communities.read', 'communities.media'],
        responses: {'communities.read': directory, 'communities.media': media},
      );
      addTearDown(host.close);
      final page = await host.adapter.read(view: 'discover', query: '');
      expect(page.items, hasLength(17));
      expect(page.next, isNull);
      for (final card in page.items) {
        expect(card.logo, isNotNull);
        expect(base64Decode(card.logo!.split(',').last), original);
      }
      expect(
        host.requests.where((r) => r.name == 'communities.media'),
        hasLength(17),
      );
    },
  );

  test('A failed image must not remove directory cards', () async {
    final host = CommunityHarness(
      legacy: true,
      capabilities: ['communities.read', 'communities.media'],
      responses: {
        'communities.read': directory,
        'communities.media': {...media, 'version': '0' * 64},
      },
    );
    addTearDown(host.close);
    final page = await host.adapter.read(view: 'discover', query: '');
    expect(page.items, hasLength(17));
    expect(page.items.every((c) => c.logo == null), isTrue);
  });

  testWidgets('Organization logo renders original above old 128KB string cap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('en'),
        ),
        home: CommunityLogo(
          data: 'data:image/png;base64,${base64Encode(original)}',
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    await settleCommunityImages(tester);
    expect(tester.takeException(), isNull);
  });
}
