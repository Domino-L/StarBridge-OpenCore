import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_account_avatar.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_avatars.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';

import 'menu_chat_media_test.dart' show photo;
import 'menu_comms_channels_test.dart' show channel;
import 'menu_friends_session_test.dart' show Port, ready;
import '../../features/communities/community_chat_media_cache_test.dart'
    show MediaPort, message;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'friends keeps a legal account photo larger than the wire limit',
    () async {
      late String large;
      final pixels = Uint8List(256 * 256 * 4);
      var seed = 17;
      for (var i = 0; i < pixels.length; i++) {
        seed = (seed * 1664525 + 1013904223) & 0xffffffff;
        pixels[i] = i % 4 == 3 ? 255 : seed >> 24;
      }
      final image = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        256,
        256,
        ui.PixelFormat.rgba8888,
        image.complete,
      );
      final decoded = await image.future;
      final bytes = await decoded.toByteData(format: ui.ImageByteFormat.png);
      decoded.dispose();
      large =
          'data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List())}';
      expect(large.length, greaterThan(128 * 1024));
      final port = Port(), views = <Map<String, Object?>>[];
      final changed = Completer<void>();
      final session = MenuFriendsSession(port, (view) {
        views.add(view);
        if ((view['identity'] as Map?)?['avatar'] != null &&
            !changed.isCompleted) {
          changed.complete();
        }
      }, identity: () => (name: 'Self', handle: 'fixture', avatar: large));
      session.show(true);
      port.reads.last.complete(ready('Peer'));
      await changed.future.timeout(const Duration(seconds: 5));
      final own = MenuFriendsView.parse(jsonEncode(views.last)).identity!;
      expect(own.avatar, startsWith('data:image/png;base64,'));
      expect(own.avatar!.length, lessThan(28000));
      session.dispose();
    },
  );
  test(
    'retired own-photo decode cannot republish after account clear',
    () async {
      var notifications = 0;
      final avatar = MenuAccountAvatar(() => notifications++);
      avatar.read(photo);
      avatar.clear();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(avatar.read(null), isNull);
      expect(notifications, 0);
      avatar.dispose();
    },
  );
  test(
    'own chat photo is normalized and does not fetch another sender',
    () async {
      final port = MediaPort()..ownAvatarImageData = photo;
      final cache = MenuChannelAvatars();
      final photos = await cache.load(port, 'a' * 32, [
        message(1, self: true, hasAvatar: false),
      ]);
      expect(photos.single, startsWith('data:image/png;base64,'));
      expect(port.calls, isEmpty);
      cache.dispose();
      await port.changes.close();
    },
  );
  test('portrait table reuses thumbnail and rejects unsafe media', () {
    final data = channel()..['portraits'] = {'p0': photo};
    for (final row in data['rows'] as List) {
      row['portrait'] = 'p0';
    }
    expect(
      MenuFeatureView.parse(data).rows.every((row) => row.avatar == photo),
      isTrue,
    );
    data['portraits'] = {'p0': 'https://not-for-renderer.invalid/avatar.png'};
    expect(MenuFeatureView.parse(data).state, 'unavailable');
  });
}
