import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_avatars.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import 'dart:convert';

import '../../features/communities/community_chat_media_cache_test.dart';
import 'menu_chat_media_test.dart' show photo;
import 'menu_comms_session_test.dart' show Port, peer;

class BackgroundSession extends MenuFeatureSession {
  BackgroundSession(void Function(Map<String, Object?>) publish)
    : super(publish, const Stream<void>.empty());
  Completer<Map<String, Object?>>? pending;
  final ready = <String, Object?>{'state': 'ready', 'rows': const []};
  @override
  bool get backgroundReads => true;
  @override
  Map<String, Object?> get readingView => ready;
  @override
  Future<Map<String, Object?>> read() async =>
      pending == null ? ready : pending!.future;
  @override
  void reset() {}
  @override
  Future<void> closePort() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'automatic refresh never publishes a loading state over existing chat',
    () async {
      final views = <Map<String, Object?>>[];
      final session = BackgroundSession(views.add);
      addTearDown(session.dispose);
      session.show(true);
      await Future<void>.delayed(Duration.zero);
      views.clear();
      session.pending = Completer();
      final refresh = session.refresh(silent: true);
      expect(
        views.where((v) => v['refreshing'] == true || v['busy'] == true),
        isEmpty,
      );
      session.pending!.complete(session.ready);
      await refresh;
    },
  );
  test(
    'own chat photo does not depend on an unrelated attachment request',
    () async {
      final port = MediaPort()
        ..ownAvatarImageData = photo
        ..fail = true;
      final avatars = MenuChannelAvatars();
      addTearDown(avatars.dispose);
      addTearDown(port.changes.close);
      final photos = await avatars.load(port, 'a' * 32, [
        message(1, self: true, attachment: true),
      ]);
      expect(photos.single, startsWith('data:image/png;base64,'));
      expect(port.calls, isEmpty);
    },
  );
  testWidgets(
    'private automatic polling retains send authority, draft and quiet history',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, views.add)..show(true);
      port.directories.single.complete([peer('A')]);
      await tester.pump();
      final key = MenuCommsView.parse(jsonEncode(views.last)).rows.single.key;
      session.act('select', key);
      port.histories.last.reply.complete(
        DirectPage(
          'secret-A',
          [DirectMessage(1, 'm1', true, 'hello', DateTime.utc(2026), null)],
          1,
          1,
          false,
          'friend',
          canSend: true,
        ),
      );
      await tester.pump();
      expect(views.last['canSend'], true);
      views.clear();
      await tester.pump(const Duration(seconds: 3));
      expect(
        views,
        isEmpty,
        reason: 'poll start is invisible, not a loading publication',
      );
      port.histories.last.reply.completeError(
        const DirectReadFailure('unavailable'),
      );
      await tester.pump();
      final retained = MenuCommsView.parse(jsonEncode(views.last));
      expect(retained.messages.single.text, 'hello');
      expect(retained.refreshing, false);
      expect(retained.notice, isEmpty);
      expect(retained.canSend, true);
      session.dispose();
      await tester.pump(const Duration(seconds: 15));
    },
  );
  test('automatic receipt does not lock the editor or cancel a read', () async {
    final views = <Map<String, Object?>>[];
    final session = BackgroundSession(views.add)..show(true);
    addTearDown(session.dispose);
    await Future<void>.delayed(Duration.zero);
    final receipt = Completer<void>();
    final key =
        session.button(
              'read receipt',
              (_) => receipt.future,
              silent: true,
            )['key']
            as String;
    views.clear();
    session.act(key, '');
    expect(views, isEmpty);
    receipt.complete();
    await Future<void>.delayed(Duration.zero);
    expect(views, isEmpty);
    session.act(key, '');
    expect(
      views,
      isEmpty,
      reason: 'a retired automatic receipt is not an interactive stale-command error',
    );
  });
}
