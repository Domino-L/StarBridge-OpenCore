import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_app.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../message_reception_owner_test.dart' as owner;
import 'social_window_test.dart' as fixture;

void main() {
  setUpAll(loadFonts);
  for (final healthy in [true, false]) {
    testWidgets('unread plus main plus actual detached app share one directory '
        'clock with healthy=$healthy; child history stays independent', (
      t,
    ) async {
      final f = owner.Fixture();
      f.backend.healthy = healthy;
      final main = DirectMessagesModule(f.a);
      await main.refresh();
      await main.open(main.rows.single);
      main.editDraft('main unsent draft');
      final lease = main.observeVisibleReception(() => true);
      final inbox = NotificationInboxController(null);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: f.b,
        inbox: inbox,
        navigate: (_) async {},
      );
      const primary = MethodChannel('starbridge/messages-primary');
      const surface = MethodChannel('starbridge/messages-surface');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(primary, (call) async {
        if (call.method == 'show') return true;
        return fixture.native(surface.name, call.method, call.arguments);
      });
      messenger.setMockMethodCallHandler(surface, (call) async {
        if (call.method == 'ready') return binding.snapshot;
        if (call.method == 'rpc') {
          return fixture.native(primary.name, 'rpc', call.arguments);
        }
        return true;
      });
      var cleaned = false;
      Future<void> cleanup() async {
        if (cleaned) return;
        cleaned = true;
        await t.pumpWidget(const SizedBox());
        lease.dispose();
        main.dispose();
        binding.dispose();
        inbox.dispose();
        await f.close();
        await t.pump();
        messenger.setMockMethodCallHandler(primary, null);
        messenger.setMockMethodCallHandler(surface, null);
      }

      addTearDown(cleanup);
      await binding.open(target: f.backend.peer);
      await t.pumpWidget(const SocialWindowApp(kind: 'messages'));
      await t.pumpAndSettle();
      await fixture.native(primary.name, 'viewportActive', {
        'opening': binding.snapshot['opening'],
        'active': true,
      });
      await fixture.native(surface.name, 'viewportActive', true);
      await t.pumpAndSettle();
      final start = owner.total(f.backend.directories);
      final mainHistory = f.backend.histories['a'] ?? 0,
          childHistory = f.backend.histories['b'] ?? 0;
      await owner.seconds(t, 20);
      final quietStart = owner.total(f.backend.directories);
      await owner.seconds(t, 40);
      final directories = owner.total(f.backend.directories) - start;
      final mainReads = (f.backend.histories['a'] ?? 0) - mainHistory;
      final childReads = (f.backend.histories['b'] ?? 0) - childHistory;
      debugPrint(
        'COMPOSED_RECEPTION healthy=$healthy virtualSeconds=60 directory=$directories mainHistory=$mainReads childHistory=$childReads byOwner=${f.backend.directories}',
      );
      expect(f.backend.directories.keys, ['unread']);
      expect(f.backend.histories.containsKey('unread'), false);
      expect(main.draft, 'main unsent draft');
      if (healthy) {
        expect(
          owner.total(f.backend.directories),
          quietStart,
          reason:
              'Steady healthy reception must stop all periodic directory IO',
        );
        expect(directories, lessThanOrEqualTo(2));
        expect(mainReads, lessThanOrEqualTo(2));
        expect(childReads, lessThanOrEqualTo(2));
      } else {
        expect(directories, inInclusiveRange(7, 11));
        expect(mainReads, inInclusiveRange(7, 11));
        expect(childReads, inInclusiveRange(7, 12));
        f.backend.arrived = true;
        await owner.seconds(t, 8);
        expect(main.messages.single.text, 'Scoped late arrival');
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                widget.data == 'Scoped late arrival',
          ),
          findsOneWidget,
          reason: 'The actual detached viewport must display a late message within eight seconds without a push',
        );
        expect(main.draft, 'main unsent draft');
      }
      await cleanup();
      expect(t.takeException(), isNull);
    });
  }
}
