import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/composition/app_activity_listener.dart';
import 'package:starbridge_flutter/app/composition/app_activity_presence.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

void main() {
  testWidgets(
    'away begins after 15 inactive minutes and interaction resumes immediately',
    (tester) async {
      var elapsed = Duration.zero;
      final activity = AppActivityPresence(elapsed: () => elapsed);
      addTearDown(activity.dispose);
      Future<void> advance(Duration delta) async {
        elapsed += delta;
        await tester.pump(delta);
      }

      activity.start();
      await advance(const Duration(minutes: 14, seconds: 59));
      expect(activity.value, isFalse);
      await advance(const Duration(seconds: 1));
      expect(activity.value, isTrue);
      activity.recordInteraction();
      expect(activity.value, isFalse);
      await advance(const Duration(minutes: 14));
      activity.recordInteraction();
      await advance(const Duration(minutes: 1));
      expect(activity.value, isFalse);
      await advance(const Duration(minutes: 14));
      expect(activity.value, isTrue);
      activity.stop();
      activity.start();
      expect(activity.value, isFalse);
      activity.stop();
      await advance(const Duration(hours: 1));
      expect(activity.value, isFalse);
    },
  );

  testWidgets(
    'activity includes pointer, scrolling and keyboard without consuming input',
    (tester) async {
      var elapsed = Duration.zero;
      final activity = AppActivityPresence(elapsed: () => elapsed);
      var presses = 0;
      var keys = 0;
      Future<void> becomeAway() async {
        elapsed += const Duration(minutes: 15);
        await tester.pump(const Duration(minutes: 15));
        expect(activity.value, isTrue);
      }

      await tester.pumpWidget(
        AppActivityListener(
          activity: activity,
          child: MaterialApp(
            home: Scaffold(
              body: Focus(
                autofocus: true,
                onKeyEvent: (_, event) {
                  keys++;
                  return KeyEventResult.ignored;
                },
                child: TextButton(
                  onPressed: () => presses++,
                  child: const Text('Tap'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await becomeAway();
      await tester.tap(find.text('Tap'));
      expect(activity.value, isFalse);
      expect(presses, 1);
      await becomeAway();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(activity.value, isFalse);
      expect(keys, greaterThan(0));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(40, 40));
      await becomeAway();
      await mouse.moveTo(const Offset(50, 50));
      expect(activity.value, isFalse);
      await becomeAway();
      tester.binding.handlePointerEvent(
        const PointerScrollEvent(
          position: Offset(50, 50),
          scrollDelta: Offset(0, 50),
        ),
      );
      expect(activity.value, isFalse);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      elapsed += const Duration(hours: 1);
      await tester.pump(const Duration(hours: 1));
      expect(activity.value, isFalse);
      activity.dispose();
    },
  );

  test('away requires app connectivity, yields to gameplay and does not hide outages', () async {
    final account = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    final away = ValueNotifier(false);
    final game = ValueNotifier(GamePresenceState.notRunning);
    final base = InMemoryShellChrome(
      initial: InMemoryShellChrome.hostConnectedProjection,
    );
    final chrome = AccountShellChrome(
      base: base,
      account: account,
      appAway: away,
      gamePresence: game,
    );
    addTearDown(() {
      chrome.dispose();
      account.dispose();
      away.dispose();
      game.dispose();
    });
    away.value = true;
    expect(chrome.projection.value.presenceKey, 'presence.unknown');
    await account.initialize();
    expect(chrome.projection.value.presenceKey, 'presence.away');
    expect(chrome.projection.value.displayPresenceKey, 'presence.away');
    game.value = GamePresenceState.running;
    expect(chrome.projection.value.presenceKey, 'presence.online');
    expect(chrome.projection.value.displayPresenceKey, 'presence.inGame');
    game.value = GamePresenceState.notRunning;
    expect(chrome.projection.value.presenceKey, 'presence.away');
    away.value = false;
    expect(chrome.projection.value.presenceKey, 'presence.online');
    away.value = true;
    base.replace(InMemoryShellChrome.disconnectedProjection);
    expect(chrome.projection.value.presenceKey, 'presence.unknown');
    expect(chrome.projection.value.connectionIssue, isNotNull);
    base.replace(InMemoryShellChrome.hostConnectedProjection);
    expect(chrome.projection.value.presenceKey, 'presence.away');
    await account.logout();
    expect(chrome.projection.value.presenceKey, 'presence.offline');
  });
}
