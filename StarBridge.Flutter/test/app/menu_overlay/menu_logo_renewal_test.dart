import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_directory_logos.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'menu_organization_renewal_test.dart' show RenewingPort;
import 'menu_chat_media_test.dart' show photo;

class DeferredLogoPort extends RenewingPort {
  final media = Completer<void>();
  int mediaReads = 0;
  @override
  CommunityCard get card => CommunityCard(
    targetRef: super.card.targetRef,
    organizationRef: organization,
    relationship: relationship,
    name: 'Fixture',
    logoDeferred: true,
  );
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    mediaReads++;
    await media.future;
    final bytes = base64Decode(photo.split(',').last);
    return {
      'schemaVersion': 1,
      'kind': kind,
      'memberRef': null,
      'offset': 0,
      'version': sha256.convert(bytes).toString(),
      'mimeType': 'image/png',
      'totalBytes': bytes.length,
      'next': null,
      'data': base64Encode(bytes),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final revoked in [false, true]) {
    test(
      'slow logo survives renewed handle but never revoked membership: $revoked',
      () async {
        final port = DeferredLogoPort();
        final updates = <String>[];
        final logos = MenuDirectoryLogos(
          port,
          (target, _) => updates.add(target),
        );
        addTearDown(logos.dispose);
        addTearDown(port.close);
        await logos.read(port.card);
        port.renewal++;
        logos.retain(revoked ? [] : [port.card]);
        if (!revoked) await logos.read(port.card);
        expect(port.mediaReads, 1);
        port.media.complete();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(updates, revoked ? isEmpty : [port.card.targetRef]);
        if (!revoked) expect(await logos.read(port.card), isNotNull);
      },
    );
  }
}
