import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_directory_logos.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_images.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';

import 'menu_directory_logos_test.dart' show MembersOnlyPort;
import 'menu_chat_media_test.dart' show photo;
import '../../features/settings/image_maintenance_menu_boundaries_test.dart'
    show HeldDirectoryPort;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('retired parent metadata has no inline bytes and cannot start a new logo conversion', () async {
    final port = HeldDirectoryPort()..gate = Completer<void>();
    final updates = <String?>[];
    final logos = MenuDirectoryLogos(port, (_, image) => updates.add(image));
    try {
      final reading = logos.readDirectory(view: 'mine', query: '');
      await port.arrived.future;
      logos.beginImageMaintenance();
      logos.endImageMaintenance();
      port.gate!.complete();
      final old = await reading;
      expect(old.items.single.logo, isNull);
      expect(await logos.read(old.items.single, waitForImage: true), isNull);
      expect(updates, isEmpty);
      port.gate = null;
      final fresh = await logos.readDirectory(view: 'mine', query: '');
      expect(
        await logos.read(fresh.items.single, waitForImage: true),
        isNotNull,
      );
      expect(updates, hasLength(1));
    } finally {
      logos.dispose();
      await port.close();
    }
  });
  test('foreground timeout and purge retain three actual decoder workers until their old tasks finish', () async {
    final port = MembersOnlyPort();
    final gate = Completer<void>(), started = Completer<void>();
    final updates = <String>[];
    var active = 0, peak = 0, calls = 0;
    final logos = MenuDirectoryLogos(
      port,
      (target, _) => updates.add(target),
      decoder: (bytes, width) async {
        calls++;
        active++;
        if (active > peak) peak = active;
        if (calls == 3) started.complete();
        try {
          await gate.future;
          return await decodeCommunityImage(bytes, width);
        } finally {
          active--;
        }
      },
    );
    CommunityCard card(int index) => CommunityCard(
      targetRef: '$index' * 32,
      name: 'Fixture $index',
      logo:
          'data:image/png;base64,${base64Encode([...base64Decode(photo.substring(22)), index])}',
    );
    try {
      final old = [
        for (var i = 1; i <= 3; i++) logos.read(card(i), waitForImage: true),
      ];
      await started.future.timeout(const Duration(seconds: 3));
      expect(
        await Future.wait(old),
        [null, null, null],
        reason: 'Foreground has a 2s paint budget, not cancellation authority.',
      );
      expect(active, 3);
      logos.beginImageMaintenance();
      logos.endImageMaintenance();
      final fresh = logos.read(card(4), waitForImage: true);
      expect(calls, 3);
      expect(active, 3);
      gate.complete();
      expect(await fresh, isNotNull);
      expect(calls, 4);
      expect(peak, 3);
      expect(updates, ['4' * 32]);
    } finally {
      if (!gate.isCompleted) gate.complete();
      logos.dispose();
      await port.close();
    }
  });
  test('organization image projection keeps member photos, unknown send state and drafts', () {
    final protected = {
      'draft': 'unsent text',
      'sendStatus': 'unknown',
      'nonce': 'local-only',
      'messages': [
        {'avatar': 'member-photo', 'text': 'message'},
      ],
    };
    final view = {
      'scope': 'same-scope',
      'chat': protected,
      'channels': [
        {'avatar': photo, 'title': 'Organization'},
      ],
      'organization': {
        'tab': 'members',
        'logo': photo,
        'navigation': [
          {'avatar': photo, 'key': 'same-grant'},
        ],
        'rows': [
          {'avatar': 'protected-member-photo', 'name': 'Member'},
        ],
      },
    };
    final cleared = MenuOrganizationImages.strip(view);
    expect(cleared['chat'], same(protected));
    expect(
      (cleared['organization'] as Map)['rows'],
      (view['organization'] as Map)['rows'],
    );
    expect((cleared['organization'] as Map)['logo'], isNull);
    expect((cleared['organization'] as Map)['navigation'], [
      containsPair('avatar', null),
    ]);
    expect(cleared['scope'], 'same-scope');
  });
}
