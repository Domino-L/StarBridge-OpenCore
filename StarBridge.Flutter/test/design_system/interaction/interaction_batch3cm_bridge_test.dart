import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_read_feedback.dart';
import 'package:starbridge_flutter/platform/window/menu_window_transport.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_read_source_argument.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_conversation_snapshot.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_binding.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_comms_session_test.dart' as comms;
import '../../app/menu_overlay/menu_friends_session_test.dart' as friends;
import '../../app/friends_window/friends_window_app_test.dart' show snapshot;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3ca_test.dart' show fire;
import 'interaction_batch3cm_test.dart' show Feature, feedback;

const codec = StandardMethodCodec();
Future<Object?> incoming(
  MethodChannel channel,
  String method,
  Object? args,
) async {
  final result = Completer<Object?>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall(method, args)),
        (reply) =>
            result.complete(reply == null ? null : codec.decodeEnvelope(reply)),
      );
  return result.future;
}

void main() {
  for (final source in [
    null,
    'pointer',
    'keyboard',
    'programmatic',
    'untrusted',
  ]) {
    testWidgets(
      '$source primary menu validates original intent before actual read attestation',
      (t) async {
        const channel = MethodChannel('starbridge/menu-primary');
        final messenger = t.binding.defaultBinaryMessenger,
            calls = <MethodCall>[];
        final port = comms.Port(), people = friends.Port();
        final privateViews = <Map<String, Object?>>[],
            friendViews = <Map<String, Object?>>[];
        final events = StreamController<void>.broadcast(sync: true);
        late Feature feature;
        int? request;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'preview') {
            request = (call.arguments as Map)['request'] as int;
            return 7;
          }
          return null;
        });
        final window = MethodChannelMenuPreviewWindow(
          lifetime: MenuWindowLifetime(),
          friends: (publish) => MenuFriendsSession(people, (view) {
            friendViews.add(view);
            publish(view);
          }),
          comms: (publish) => MenuCommsSession(port, (view) {
            privateViews.add(view);
            publish(view);
          }),
          features: {
            'rooms': (publish) => feature = Feature(publish, events.stream),
          },
        );
        try {
          final opening = window.openLive(
            contextLabel: 'Test',
            returnLabel: 'Return',
            settingsLabel: 'Settings',
          );
          await t.pump();
          await incoming(channel, 'state', {
            'request': request,
            'state': 'visible',
          });
          expect(await opening, isTrue);
          await incoming(channel, 'commsVisible', {
            'opening': 6,
            'visible': true,
            'motionSource': source,
          });
          expect(
            port.directories,
            isEmpty,
            reason: 'source does not bypass opening',
          );
          await incoming(channel, 'commsVisible', {
            'opening': 7,
            'visible': true,
            'motionSource': source,
          });
          final expected = source == 'pointer'
              ? MenuReadOrigin.pointer
              : source == 'keyboard'
              ? MenuReadOrigin.keyboard
              : MenuReadOrigin.programmatic;
          expect(feedback(privateViews.last)?.origin, expected);
          port.directories.last.complete([]);
          await t.pump();
          expect(feedback(privateViews.last), isNull);
          await incoming(channel, 'friendsVisible', {
            'opening': 7,
            'visible': true,
            'motionSource': source,
          });
          expect(feedback(friendViews.last)?.origin, expected);
          people.reads.last.complete(friends.ready('Current'));
          await t.pump();
          await incoming(channel, 'friendsAction', {
            'opening': 7,
            'action': 'refresh',
            'key': '',
            'value': '',
            'motionSource': source,
          });
          expect(feedback(friendViews.last)?.origin, expected);
          people.reads.last.complete(friends.ready('Current'));
          await t.pump();
          await incoming(channel, 'featureVisible', {
            'opening': 7,
            'tool': 'rooms',
            'visible': true,
            'motionSource': source,
          });
          expect(feedback(feature.currentView)?.origin, expected);
          feature.reads.last.complete({'title': 'Ready'});
          await t.pump();
          await incoming(channel, 'featureAction', {
            'opening': 7,
            'tool': 'rooms',
            'key': 'refresh',
            'value': '',
            'motionSource': source,
          });
          expect(feedback(feature.currentView)?.origin, expected);
          feature.reads.last.complete({'title': 'Ready'});
          await t.pump();
          final readCount = people.reads.length;
          await incoming(channel, 'friendsAction', {
            'opening': 6,
            'action': 'refresh',
            'key': '',
            'value': '',
            'motionSource': 'pointer',
          });
          expect(people.reads.length, readCount);
          expect(currentMenuReadOrigin, MenuReadOrigin.programmatic);
        } finally {
          window.dispose();
          await events.close();
          await t.pump(const Duration(seconds: 16));
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
    );
    testWidgets(
      '$source separate friends binding preserves opening/revision/scope and read source',
      (t) async {
        const channel = MethodChannel('starbridge/friends-primary');
        final messenger = t.binding.defaultBinaryMessenger,
            calls = <MethodCall>[],
            port = friends.Port();
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'show' ? true : null;
        });
        final binding = FriendsWindowBinding(
          create: (publish) => MenuFriendsSession(port, publish),
          openChat: (_, _) async {},
          openMessages: (_) async {},
          openProfile: (_) async {},
        );
        Map current() =>
            calls.lastWhere((c) => c.method == 'snapshot').arguments as Map;
        Map view() => jsonDecode(current()['view'] as String) as Map;
        try {
          expect(await binding.open(), isTrue);
          port.reads.last.complete(friends.ready('Current'));
          await t.pump();
          final args = {
            'opening': current()['opening'],
            'revision': current()['revision'],
            'scope': view()['scope'],
            'action': 'refresh',
            'key': '',
            'value': '',
            'motionSource': source,
          };
          expect(
            await incoming(channel, 'action', {...args, 'revision': -1}),
            isFalse,
          );
          expect(port.reads, hasLength(1));
          expect(await incoming(channel, 'action', args), isTrue);
          await t.pump();
          expect(
            feedback(view())?.origin,
            source == 'pointer'
                ? MenuReadOrigin.pointer
                : source == 'keyboard'
                ? MenuReadOrigin.keyboard
                : MenuReadOrigin.programmatic,
          );
          port.reads.last.complete(friends.ready('Current'));
          await t.pump();
          expect(feedback(view()), isNull);
          expect(
            await incoming(channel, 'hidden', {
              'opening': current()['opening'],
            }),
            isTrue,
          );
          expect(await incoming(channel, 'action', args), isFalse);
          expect(port.reads, hasLength(2));
        } finally {
          binding.dispose();
          await t.pump(const Duration(seconds: 11));
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
    );
  }
  for (final source in InteractionSource.values) {
    test(
      '$source argument annotation is active-only, immutable and limited to read-capable intents',
      () {
        final read = {'opening': 1, 'action': 'retry', 'key': ''};
        expect(menuReadSourceArgument('commsAction', read), same(read));
        final annotated = runStarBridgeSynchronousActivation(
          source,
          () => menuReadSourceArgument('commsAction', read),
        );
        expect(
          (annotated as Map)['motionSource'],
          source == InteractionSource.programmatic ? isNull : source.name,
        );
        expect(read.containsKey('motionSource'), isFalse);
        for (final write in ['send', 'edit']) {
          final argument = {'action': write};
          expect(
            runStarBridgeSynchronousActivation(
              source,
              () => menuReadSourceArgument('commsCompose', argument),
            ),
            same(argument),
          );
        }
        expect(menuReadSourceArgument('dismiss', 1), 1);
      },
    );
  }
  testWidgets('method origin expires before a delayed handler continuation', (
    t,
  ) async {
    final seen = <MenuReadOrigin>[];
    final handler = menuReadMethodHandler((call) async {
      seen.add(currentMenuReadOrigin);
      await Future<void>.value();
      seen.add(currentMenuReadOrigin);
    });
    final pending = handler(
      const MethodCall('commsAction', {
        'action': 'retry',
        'motionSource': 'pointer',
      }),
    );
    await t.pump();
    await pending;
    expect(seen, [MenuReadOrigin.pointer, MenuReadOrigin.programmatic]);
  });
  test('cached display removes transient read and command grants without mutating input', () {
    final raw = {
      'receipts': {'0': 'r1'},
      'readFeedback': const MenuReadFeedback(1, MenuReadOrigin.pointer).wire,
      'messages': [
        {'text': 'Kept', 'attachmentKey': 'i1'},
      ],
    };
    final cached = menuCachedHistory(raw);
    expect(cached['readFeedback'], isNull);
    expect(cached['receipts'], isEmpty);
    expect((cached['messages'] as List).single, {
      'text': 'Kept',
      'attachmentKey': null,
    });
    expect(raw['readFeedback'], isNotNull);
    expect(((raw['messages'] as List).single as Map)['attachmentKey'], 'i1');
  });
  test('native source allowlist is bounded (source-only, not native compilation evidence)', () {
    final native = File('windows/runner/menu_overlay_bridge.cpp')
        .readAsStringSync();
    expect(native, contains('std::string ReadMotionSource(const Map& map)'));
    expect(native, contains('*source == "pointer" || *source == "keyboard"'));
    expect(
      RegExp(r'Value\(ReadMotionSource\(\*args\)\)').allMatches(native),
      hasLength(5),
    );
    final friendsNative = File('windows/runner/friends_window_bridge.cpp')
        .readAsStringSync();
    expect(
      friendsNative,
      contains('primary_.InvokeMethod("action", std::make_unique<Value>(*map)'),
    );
  });
  for (final source in ['pointer', 'keyboard', 'reader']) {
    testWidgets(
      '$source actual friend surface serializes its activation source',
      (t) async {
        const channel = MethodChannel('starbridge/friends-surface');
        final messenger = t.binding.defaultBinaryMessenger,
            calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'ready' ? snapshot() : true;
        });
        size(t, const Size(900, 1000));
        final semantics = t.ensureSemantics();
        try {
          await t.pumpWidget(const FriendsWindowApp());
          await t.pumpAndSettle();
          await fire(t, source, find.byKey(const ValueKey('friends-refresh-')));
          final args =
              calls.singleWhere((c) => c.method == 'action').arguments as Map;
          expect(args['action'], 'refresh');
          expect(
            args['motionSource'],
            source == 'pointer' ? 'pointer' : 'keyboard',
          );
          expect(args['scope'], 'friends1');
        } finally {
          semantics.dispose();
          await t.pumpWidget(const SizedBox());
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
    );
  }
}
