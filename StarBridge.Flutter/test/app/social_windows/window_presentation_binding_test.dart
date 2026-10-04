import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_binding.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import '../friends_window/friends_window_binding_test.dart' as friends;
import 'social_window_test.dart' as social;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['friends', 'messages', 'notifications']) {
    testWidgets('$kind publishes live preferences without changing account scope', (tester) async {
      final preferences = InMemoryAppPreferences();
      final calls = <MethodCall>[];
      final channel = MethodChannel('starbridge/$kind-primary');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'show' ? true : null;
      });
      final inbox = NotificationInboxController(null);
      final friendBinding = kind != 'friends' ? null : FriendsWindowBinding(
        preferences: preferences,
        create: (publish) => MenuFriendsSession(friends.Port(), publish),
        openChat: (_, _) async {}, openMessages: (_) async {}, openProfile: (_) async {},
      );
      final socialBinding = kind == 'friends' ? null : SocialWindowBinding(
        kind: kind, preferences: preferences, messages: social.Port(), inbox: inbox,
        navigate: (_) async {},
      );
      await (friendBinding?.open() ?? socialBinding!.open());
      await tester.pump();
      Map latest() => calls.lastWhere((call) => call.method == 'show' || call.method == 'snapshot').arguments as Map;
      final originalScope = (jsonDecode(latest()['view'] as String) as Map)['scope'];
      await preferences.setAppearanceMode(AppearanceMode.light);
      await tester.pump();
      expect((latest()['presentation'] as Map)['appearanceMode'], 'light');
      expect((jsonDecode(latest()['view'] as String) as Map)['scope'], originalScope);
      friendBinding?.dispose();
      socialBinding?.dispose();
      await tester.pump();
      final afterDispose = calls.length;
      await preferences.setAppearanceMode(AppearanceMode.dark);
      await tester.pump();
      expect(calls.length, afterDispose);
      preferences.dispose();
      inbox.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
  }
}
