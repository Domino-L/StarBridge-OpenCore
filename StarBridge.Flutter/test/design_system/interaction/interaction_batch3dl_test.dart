import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dk_test.dart' show activate;
import 'interaction_batch3dj_test.dart' show visibleFrames, remove;
import 'interaction_batch3aa_test.dart' show reader;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/direct_messages/direct_message_send_test.dart' as direct;

InboxItem notice(String ref, String target) => InboxItem(
  ref,
  'system',
  'action_required',
  'Notice $ref',
  'Exact original body',
  DateTime(2026),
  false,
  target,
  'Open',
  true,
);

class Inbox extends NotificationInboxController {
  Inbox() : super(null) {
    ready = true;
    items = [
      notice('safety', 'account_safety'),
      notice('rooms', 'room_invitations'),
    ];
  }
  int reads = 0;
  final writes = <List<InboxItem>>[];
  final order = <String>[];
  Completer<bool>? next;
  bool disposed = false;
  void announce() => notifyListeners();
  @override
  Future<bool> refresh({bool quiet = false, bool reuseFresh = false}) async {
    if (busy) return false;
    reads++;
    if (next == null) return true;
    final result = next!;
    busy = true;
    notifyListeners();
    try {
      final ok = await result.future;
      if (!disposed) {
        ready = true;
        error = ok ? null : 'read';
      }
      return ok;
    } finally {
      if (!disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<bool> markRead(List<InboxItem> selected) async {
    order.add('read');
    writes.add(selected);
    return false;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class Messages extends direct.Sender {
  Completer<List<Conversation>>? nextDirectory;
  int reads = 0;
  @override
  Future<List<Conversation>> directory() {
    reads++;
    return nextDirectory?.future ?? super.directory();
  }
}

InteractionData waitData(WidgetTester t) => InteractionScope.of(
  t.element(
    find.descendant(
      of: find.byType(SocialReadActivity),
      matching: find.byType(SuiteBusyFrame),
    ),
  ),
);

Widget inboxHost(
  Inbox inbox,
  InteractionSuite suite, {
  bool reduce = false,
  InteractionSource? opening,
  VoidCallback? safety,
}) => scopedApp(
  NativeViewportScope(
    active: false,
    child: Builder(
      builder: (context) {
        final child = NotificationInboxPage(
          controller: inbox,
          openSafety: safety,
        );
        return opening == null
            ? child
            : starBridgeInitialReadViewport(
                context,
                source: opening,
                child: child,
              );
      },
    ),
  ),
  suite,
  reduce: reduce,
);

Future<void> input(
  WidgetTester t,
  String source,
  String key,
  String label,
) async {
  if (source == 'reader') {
    reader(t, label);
  } else {
    await activate(t, key, keyboard: source == 'keyboard');
  }
  await visibleFrames(t);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source notification refresh keeps content, no duplicate read and live reduce',
        (t) async {
          size(t, const Size(1000, 950));
          final inbox = Inbox();
          final semantics = t.ensureSemantics();
          await t.pumpWidget(inboxHost(inbox, suite));
          await t.pumpAndSettle();
          expect(inbox.reads, 1);
          inbox.next = Completer<bool>();
          await input(t, source, 'notification-refresh', '刷新');
          expect(inbox.reads, 2);
          expect(find.text('Notice rooms'), findsOneWidget);
          expect(waitData(t).reduceMotion, source != 'pointer');
          if (source != 'pointer') expect(t.hasRunningAnimations, isFalse);
          await t.tapAt(
            t.getCenter(find.byKey(const Key('notification-refresh'))),
          );
          await t.pump();
          expect(inbox.reads, 2);
          await t.pumpWidget(inboxHost(inbox, suite, reduce: true));
          await visibleFrames(t);
          expect(waitData(t).reduceMotion, isTrue);
          expect(t.hasRunningAnimations, isFalse);
          expect(inbox.writes, isEmpty);
          inbox.next!.complete(false);
          await t.pumpAndSettle();
          expect(find.byType(SocialReadActivity), findsNothing);
          expect(find.text('Notice rooms'), findsOneWidget);
          expect(inbox.error, 'read');
          await remove(t);
          semantics.dispose();
          inbox.dispose();
          expect(t.takeException(), isNull);
        },
      );

      testWidgets(
        '$suite $source notification destination retains exact read then navigation order',
        (t) async {
          size(t, const Size(1100, 950));
          final inbox = Inbox();
          final semantics = t.ensureSemantics();
          Widget host() => scopedApp(
            NativeViewportScope(
              active: false,
              child: Actions(
                actions: {
                  OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                    onInvoke: (intent) {
                      inbox.order.add(intent.route);
                      return null;
                    },
                  ),
                },
                child: NotificationInboxPage(
                  controller: inbox,
                  openSafety: () => inbox.order.add('safety'),
                ),
              ),
            ),
            suite,
          );
          await t.pumpWidget(host());
          await t.pumpAndSettle();
          if (source == 'reader') {
            reader(t, '前往相关页面');
          } else {
            final key = const ValueKey(('notification-destination', 'rooms'));
            final node = t.widget(find.byKey(key));
            if (source == 'keyboard') {
              final focus = node is ButtonStyleButton
                  ? node.focusNode!
                  : (node as SuitePressable).focusNode!;
              focus.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              await t.tap(find.byKey(key));
            }
          }
          await visibleFrames(t);
          expect(inbox.order, ['read', '/rooms/invitations']);
          expect(inbox.writes.single.single.reference, 'rooms');
          expect(inbox.reads, 1);
          await remove(t);
          semantics.dispose();
          inbox.dispose();
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite initial keyboard wait and later passive update are static, source cannot be stolen',
      (t) async {
        size(t, const Size(1000, 950));
        final inbox = Inbox()
          ..ready = false
          ..next = Completer<bool>();
        await t.pumpWidget(
          inboxHost(inbox, suite, opening: InteractionSource.keyboard),
        );
        await visibleFrames(t);
        expect(waitData(t).reduceMotion, isTrue);
        await runStarBridgeActivation<void>(
          InteractionSource.pointer,
          () => inbox.announce(),
        );
        await visibleFrames(t);
        expect(waitData(t).reduceMotion, isTrue);
        inbox.next!.complete(true);
        await t.pumpAndSettle();
        inbox.next = Completer<bool>();
        unawaited(inbox.refresh());
        await visibleFrames(t);
        expect(waitData(t).reduceMotion, isTrue);
        expect(
          t.widget<SocialReadActivity>(find.byType(SocialReadActivity)).opening,
          isFalse,
        );
        inbox.next!.complete(true);
        await t.pumpAndSettle();
        await remove(t);
        inbox.dispose();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite direct refresh retains draft/history, keyboard phase then pointer phase',
      (t) async {
        size(t, const Size(1200, 950));
        final port = Messages();
        final module = await direct.opened(port);
        module.editDraft('Retained exact draft');
        final selected = module.selected, history = List.of(module.messages);
        await t.pumpWidget(
          scopedApp(
            NativeViewportScope(
              active: false,
              child: DirectMessagesPage(
                createPort: () => port,
                sharedModule: module,
                onBack: () {},
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        for (final source in ['keyboard', 'pointer']) {
          port.nextDirectory = Completer<List<Conversation>>();
          await activate(
            t,
            'chat-refresh-directory',
            keyboard: source == 'keyboard',
          );
          await visibleFrames(t);
          expect(waitData(t).reduceMotion, source == 'keyboard');
          expect(module.draft, 'Retained exact draft');
          expect(module.selected!.ref, selected!.ref);
          expect(module.selected!.conversationKey, selected.conversationKey);
          expect(module.messages, history);
          port.nextDirectory!.completeError(StateError('offline fixture'));
          await t.pumpAndSettle();
          expect(module.directoryError, isNotNull);
          expect(module.draft, 'Retained exact draft');
          expect(port.writes, isEmpty);
        }
        await remove(t);
        module.dispose();
        expect(t.takeException(), isNull);
      },
    );
  }
}
