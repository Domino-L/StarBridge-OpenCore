import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_binding.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/social_windows/window_opening_source.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import 'interaction_batch3dl_test.dart';
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dk_test.dart' show activate;
import 'interaction_batch3aa_test.dart' show reader;
import 'interaction_batch3dj_test.dart' show visibleFrames, remove;
import '../../app/friends_window/friends_window_binding_test.dart' as friends;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

class BusyOwner extends ChangeNotifier {
  bool busy = false;
  int listeners = 0;
  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  void emit(bool value) {
    busy = value;
    notifyListeners();
  }
}

void main() {
  setUpAll(loadFonts);
  test('observer freezes admitted phase, ignores notifications, static passive phase, unsubscribes borrowed owner', () async {
    final owner = BusyOwner();
    final feedback = SocialReadActivityBinding(
      owner,
      () => owner.busy,
      initialRead: true,
    );
    expect(owner.listeners, 1);
    owner.emit(true);
    expect(feedback.revision, 1);
    expect(feedback.opening, isTrue);
    await runStarBridgeActivation<void>(
      InteractionSource.pointer,
      () => owner.emit(true),
    );
    expect(feedback.source, InteractionSource.programmatic);
    expect(feedback.revision, 1);
    owner.emit(false);
    await runStarBridgeActivation<void>(
      InteractionSource.keyboard,
      () => owner.emit(true),
    );
    expect(feedback.source, InteractionSource.keyboard);
    expect(feedback.revision, 2);
    expect(feedback.opening, isFalse);
    owner.emit(false);
    owner.emit(true);
    expect(feedback.source, InteractionSource.programmatic);
    expect(feedback.revision, 3);
    feedback.dispose();
    expect(owner.listeners, 0);
    owner.emit(false);
    owner.emit(true);
    expect(feedback.revision, 3);
    owner.dispose();
  });

  for (final suite in InteractionSuite.values) {
    for (final inputSource in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $inputSource account status action preserves read attempt before navigation',
        (t) async {
          size(t, const Size(1000, 900));
          final inbox = Inbox(), semantics = t.ensureSemantics();
          await t.pumpWidget(
            inboxHost(inbox, suite, safety: () => inbox.order.add('safety')),
          );
          await t.pumpAndSettle();
          final target = find.byKey(
            const ValueKey(('notification-safety', 'safety')),
          );
          if (inputSource == 'reader') {
            reader(t, '查看账号状态');
          } else if (inputSource == 'keyboard') {
            final control = t.widget(target);
            final focus = control is ButtonStyleButton
                ? control.focusNode!
                : (control as SuitePressable).focusNode!;
            focus.requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            await t.tap(target);
          }
          await visibleFrames(t);
          expect(inbox.order, ['read', 'safety']);
          expect(inbox.writes.single.single.reference, 'safety');
          await remove(t);
          semantics.dispose();
          inbox.dispose();
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite replacement busy owner cannot inherit old pointer wait and late old completion cannot alter new view',
      (t) async {
        size(t, const Size(1000, 900));
        final old = Inbox();
        Inbox current = old;
        Widget host() => scopedApp(
          NativeViewportScope(
            active: false,
            child: NotificationInboxPage(controller: current),
          ),
          suite,
        );
        await t.pumpWidget(host());
        await t.pumpAndSettle();
        old.next = Completer<bool>();
        await activate(t, 'notification-refresh');
        await visibleFrames(t);
        expect(waitData(t).reduceMotion, isFalse);
        final next = Inbox()..next = Completer<bool>();
        unawaited(next.refresh());
        current = next;
        await t.pumpWidget(host());
        await visibleFrames(t);
        expect(waitData(t).reduceMotion, isTrue);
        expect(
          t.widget<SocialReadActivity>(find.byType(SocialReadActivity)).opening,
          isFalse,
        );
        old.next!.complete(false);
        await visibleFrames(t);
        expect(find.byType(SocialReadActivity), findsOneWidget);
        expect(current.error, isNull);
        await remove(t);
        next.next!.complete(true);
        await visibleFrames(t);
        expect(find.byType(NotificationInboxPage), findsNothing);
        old.dispose();
        next.dispose();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite OS reduced motion overrides pointer activity without changing window preferences',
      (t) async {
        size(t, const Size(1000, 900));
        final inbox = Inbox();
        await t.pumpWidget(inboxHost(inbox, suite));
        await t.pumpAndSettle();
        inbox.next = Completer<bool>();
        await activate(t, 'notification-refresh');
        await visibleFrames(t);
        expect(waitData(t).reduceMotion, isFalse);
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await visibleFrames(t);
        expect(waitData(t).reduceMotion, isTrue);
        await remove(t);
        inbox.next!.complete(true);
        await t.pump();
        inbox.dispose();
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final action in ['chat', 'messages', 'profile']) {
    for (final source in ['pointer', 'keyboard', 'unknown']) {
      testWidgets(
        '$action $source source handoff occurs only after original window/target guards',
        (t) async {
          const channel = MethodChannel('starbridge/friends-primary');
          final calls = <MethodCall>[];
          final observed = <InteractionSource>[];
          final messenger = t.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(channel, (c) async {
            calls.add(c);
            return c.method == 'show' ? true : null;
          });
          Future<void> record() async {
            observed.add(captureWindowOpeningSource());
            await Future<void>.value();
            observed.add(captureWindowOpeningSource());
          }

          final binding = FriendsWindowBinding(
            create: (publish) => MenuFriendsSession(friends.Port(), publish),
            openChat: (_, current) async {
              expect(current(), isTrue);
              await record();
            },
            openMessages: (current) async {
              expect(current(), isTrue);
              await record();
            },
            openProfile: (_) => record(),
          );
          await binding.open();
          await t.pump();
          final payload =
              calls.lastWhere((c) => c.method == 'snapshot').arguments as Map;
          final view = jsonDecode(payload['view'] as String) as Map;
          final args = {
            ...payload,
            'scope': view['scope'],
            'action': action,
            'key': (view['rows'] as List).first['key'],
            'value': '',
            'motionSource': source,
          };
          expect(
            await friends.fromNative('action', {...args, 'revision': -100}),
            isFalse,
          );
          expect(observed, isEmpty);
          expect(await friends.fromNative('action', args), isTrue);
          final expected = source == 'pointer'
              ? InteractionSource.pointer
              : source == 'keyboard'
              ? InteractionSource.keyboard
              : InteractionSource.programmatic;
          expect(observed, [expected, expected]);
          expect(captureWindowOpeningSource(), InteractionSource.programmatic);
          await friends.fromNative('hidden', {'opening': payload['opening']});
          expect(await friends.fromNative('action', args), isFalse);
          expect(observed, hasLength(2));
          binding.dispose();
          await t.pump();
          messenger.setMockMethodCallHandler(channel, null);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
