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
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/platform/window/menu_live_presentation_feeds.dart';
import 'package:starbridge_flutter/platform/window/menu_social_preferences.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import 'menu_chat_media_test.dart' show photo;
import 'menu_comms_channels_test.dart' show channel;
import 'menu_friends_session_test.dart' show Port;
import 'menu_comms_session_test.dart' as comms;
import '../../features/communities/community_chat_media_cache_test.dart'
    show MediaPort, message;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'friend avatar preference applies before reads and live without network refresh',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final session = MenuFriendsSession(port, views.add);
      final feeds = MenuLivePresentationFeeds();
      Map settings(bool show) =>
          MenuSocialPreferences(showAvatars: show).toSettingsPatch();
      feeds.bindAvatars(session, settings(false));
      feeds.start(
        settings: settings(false),
        isCurrent: () => true,
        publish: (_, _) {},
      );
      session.show(true);
      port.reads.last.complete(
        FriendsReadResult(
          FriendsReadState.ready,
          snapshot: FriendsSnapshot(
            groups: {
              FriendsSection.friends: [
                FriendRow(
                  'Peer',
                  'peer',
                  'friend',
                  DateTime(2026),
                  targetRef: 'fixture-peer',
                  avatar: photo,
                ),
              ],
            },
            results: [],
          ),
        ),
      );
      await tester.pump();
      expect(
        MenuFriendsView.parse(jsonEncode(views.last)).rows.single.avatar,
        isNull,
      );
      final reads = port.reads.length;
      feeds.updateSettings(settings(true));
      await tester.pump();
      expect(
        MenuFriendsView.parse(jsonEncode(views.last)).rows.single.avatar,
        photo,
      );
      feeds.updateSettings(settings(false));
      expect(jsonEncode(views.last), isNot(contains('data:image')));
      expect(port.reads.length, reads);
      feeds.stop();
      session.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'private-chat avatar toggle clears presentation while keeping chat content',
    (tester) async {
      final port = comms.Port(), views = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, views.add);
      session.showAvatars = false;
      session.show(true);
      port.directories.last.complete([comms.peer('Peer', avatar: photo)]);
      await tester.pump();
      final rows = views.last['rows'] as List;
      expect((rows.single as Map)['avatar'], isNull);
      session.act('select', (rows.single as Map)['key'] as String);
      port.histories.last.reply.complete(
        comms.page('secret-Peer', text: 'Synthetic message'),
      );
      await tester.pump();
      expect(jsonEncode(views.last), contains('Synthetic message'));
      expect(jsonEncode(views.last), isNot(contains('data:image')));
      session.showAvatars = true;
      session.showAvatars = false;
      expect(jsonEncode(views.last), isNot(contains('data:image')));
      expect(port.sends + port.receipts, 0);
      session.dispose();
      await tester.pump();
    },
  );
  test(
    'friends keeps legal own and peer photos larger than the wire limit',
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
      port.reads.last.complete(
        FriendsReadResult(
          FriendsReadState.ready,
          snapshot: FriendsSnapshot(
            groups: {
              FriendsSection.friends: [
                FriendRow(
                  'Peer',
                  'peer',
                  'friend',
                  DateTime(2026),
                  targetRef: 'fixture-peer',
                  avatar: large,
                  shared: {'presence': 'AppOnline'},
                ),
              ],
            },
            results: [],
          ),
        ),
      );
      await changed.future.timeout(const Duration(seconds: 5));
      final own = MenuFriendsView.parse(jsonEncode(views.last)).identity!;
      expect(own.avatar, startsWith('data:image/png;base64,'));
      expect(own.avatar!.length, lessThan(28000));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final peer = MenuFriendsView.parse(jsonEncode(views.last)).rows.single;
      expect(peer.avatar, startsWith('data:image/png;base64,'));
      expect(peer.avatar!.length, lessThan(28000));
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
