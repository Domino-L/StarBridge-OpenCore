// SOURCE PREPARATION ONLY: not installed, formatted, analyzed or executed.
// Eventual approved location: test/design_system/interaction/
// auxiliary_ready_snapshot_seams_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_app.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_app.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_snapshot.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/shared/release/official_client_profile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/friends_window/friends_window_app_test.dart' as friends;
import '../../app/social_windows/social_window_test.dart' show native;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

// This adapter controls the real OS MethodChannel seam only. There is no fake
// WindowApp, preferences owner, store, receiver, reducer or acceptance algorithm.
class _Transport {
  _Transport(this.kind) : channel = MethodChannel('starbridge/$kind-surface');
  final String kind;
  final MethodChannel channel;
  final ready = Completer<Object?>();
  final calls = <MethodCall>[];
  final trace = <String>[];
  final unexpected = <String>[];
  bool readyStarted = false, readyReturned = false;

  Future<Object?> receive(MethodCall call) async {
    calls.add(call);
    if (call.method == 'ready') {
      expect(readyStarted, false, reason: 'One actual startup ready request.');
      readyStarted = true;
      trace.add('readyStarted');
      try {
        return await ready.future;
      } finally {
        readyReturned = true;
        trace.add('readyReturned');
      }
    }
    if (call.method == 'rpc') {
      final args = call.arguments as Map;
      switch (args['op']) {
        case 'directory':
          return <Object?>[];
        case 'refresh':
          return {'items': <Object?>[], 'ready': true};
        case 'viewport':
          return true;
        default:
          unexpected.add('rpc:${args['op']}');
          throw PlatformException(
            code: 'fixture.unexpected-rpc',
            message: '${args['op']}',
          );
      }
    }
    if (call.method == 'painted' || call.method == 'layout') return null;
    unexpected.add(call.method);
    throw PlatformException(
      code: 'fixture.unexpected-method',
      message: call.method,
    );
  }

  Widget app() => switch (kind) {
    'friends' => const FriendsWindowApp(),
    'tray' => const TraySurfaceApp(),
    _ => SocialWindowApp(kind: kind),
  };

  Map<String, Object?> snapshot({
    required int opening,
    required int revision,
    required InteractionSuite suite,
    required bool reduce,
    required bool dark,
  }) {
    if (kind == 'tray') {
      return {
        ...TraySurfaceSnapshot(
          scope: 700,
          revision: revision,
          state: const TrayQuickPanelState(runtime: TrayRuntimeState.running),
          interactionStyle: suite.name,
          reduceMotion: reduce,
          dark: dark,
        ).toMap(),
        // The native envelope adds these; toMap intentionally does not own them.
        'opening': opening, 'keyboard': true,
      };
    }
    return {
      if (kind == 'friends')
        ...friends.snapshot(opening: opening, revision: revision)
      else ...{
        'opening': opening,
        'revision': revision,
        'openingSource': 'keyboard',
        'view': jsonEncode({'scope': 'ready-seam-scope', 'targetVersion': 0}),
      },
      'presentation': {
        'appearanceMode': dark ? 'dark' : 'light',
        'locale': 'zh-CN',
        'interactionStyle': suite.name,
        'reduceMotion': reduce,
      },
    };
  }

  Future<void> push(WidgetTester t, Map<String, Object?> snapshot) async {
    trace.add('push');
    await native(channel.name, 'snapshot', snapshot);
    await _frames(t);
  }

  int get painted => calls.where((call) => call.method == 'painted').length;
  void noBusinessWrites() {
    expect(
      unexpected,
      isEmpty,
      reason: 'Do not hide fixture protocol errors behind App recovery.',
    );
    expect(
      calls.where(
        (call) => call.method == 'action' || call.method == 'windowControl',
      ),
      isEmpty,
    );
    expect(
      calls.where(
        (call) =>
            call.method == 'rpc' &&
            !const {
              'directory',
              'refresh',
              'viewport',
            }.contains((call.arguments as Map)['op']),
      ),
      isEmpty,
    );
    expect(calls.where((call) => call.method == 'ready'), hasLength(1));
  }
}

Future<void> _frames(WidgetTester t, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void _presentation(
  WidgetTester t,
  InteractionSuite suite, {
  required bool reduce,
  required bool dark,
}) {
  expect(find.byType(Scaffold), findsOneWidget);
  final data = InteractionScope.of(t.element(find.byType(Scaffold)));
  expect(data.suite, suite);
  expect(data.reduceMotion, reduce);
  expect(
    t.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
    dark ? Brightness.dark : Brightness.light,
  );
}

Object? _messageOwner(WidgetTester t, String kind) => kind == 'messages'
    ? t.widget<DirectMessagesPage>(find.byType(DirectMessagesPage)).sharedModule
    : null;

void _case(
  String kind,
  String name,
  Future<void> Function(WidgetTester, _Transport) body,
) {
  testWidgets('surface ready seam $kind $name', (t) async {
    final transport = _Transport(kind);
    final messenger = t.binding.defaultBinaryMessenger;
    size(t, switch (kind) {
      'friends' => const Size(392, 720),
      'tray' => const Size(336, 552),
      _ => const Size(1100, 850),
    });
    messenger.setMockMethodCallHandler(transport.channel, transport.receive);
    try {
      await t.pumpWidget(transport.app());
      await _frames(t);
      expect(transport.readyStarted, true);
      expect(transport.readyReturned, false);
      expect(transport.ready.isCompleted, false);
      await body(t, transport);
      transport.noBusinessWrites();
      expect(t.takeException(), isNull);
    } finally {
      try {
        await t.pumpWidget(const SizedBox());
        if (!transport.ready.isCompleted) transport.ready.complete(null);
        await _frames(t);
      } finally {
        messenger.setMockMethodCallHandler(transport.channel, null);
      }
    }
  }, skip: !OfficialClientProfile.advancedInteractions);
}

void main() {
  setUpAll(loadFonts);
  const kinds = ['friends', 'messages', 'notifications', 'tray'];
  // Four positive controls first: held ready is a real public startup request.
  for (final kind in kinds) {
    _case(kind, 'actual-ready-positive-without-a-push', (t, transport) async {
      transport.ready.complete(
        transport.snapshot(
          opening: 1,
          revision: 1,
          suite: InteractionSuite.rail,
          reduce: false,
          dark: false,
        ),
      );
      await _frames(t);
      expect(transport.readyReturned, true);
      _presentation(t, InteractionSuite.rail, reduce: false, dark: false);
    });
  }
  for (final kind in kinds) {
    for (final oldOpening in [false, true]) {
      _case(
        kind,
        oldOpening
            ? 'old-opening-higher-revision-ready'
            : 'same-opening-older-revision-ready',
        (t, transport) async {
          // A higher revision in an older opening must not defeat a new opening.
          final pushedOpening = oldOpening ? 2 : 1;
          final pushedRevision = oldOpening ? 1 : 2;
          final oldRevision = oldOpening ? 90 : 1;
          await transport.push(
            t,
            transport.snapshot(
              opening: pushedOpening,
              revision: pushedRevision,
              suite: InteractionSuite.glow,
              reduce: true,
              dark: true,
            ),
          );
          expect(transport.readyReturned, false);
          expect(transport.ready.isCompleted, false);
          _presentation(t, InteractionSuite.glow, reduce: true, dark: true);
          final scaffold = t.element(find.byType(Scaffold));
          final owner = _messageOwner(t, kind);
          if (kind == 'messages') expect(owner, isNotNull);
          final painted = transport.painted;

          transport.trace.add('releaseOldReady');
          transport.ready.complete(
            transport.snapshot(
              opening: 1,
              revision: oldRevision,
              suite: InteractionSuite.rail,
              reduce: false,
              dark: false,
            ),
          );
          await _frames(t);
          expect(transport.readyReturned, true);
          expect(
            transport.trace.indexOf('push'),
            lessThan(transport.trace.indexOf('readyReturned')),
          );
          _presentation(t, InteractionSuite.glow, reduce: true, dark: true);
          expect(t.element(find.byType(Scaffold)), same(scaffold));
          if (owner != null) expect(_messageOwner(t, kind), same(owner));
          expect(
            transport.painted,
            painted,
            reason: 'Rejected stale ready must not publish a new painted acknowledgement.',
          );

          // Prove the actual consumer remains subscribed after rejecting old data.
          await transport.push(
            t,
            transport.snapshot(
              opening: pushedOpening,
              revision: pushedRevision + 1,
              suite: InteractionSuite.scan,
              reduce: false,
              dark: false,
            ),
          );
          _presentation(t, InteractionSuite.scan, reduce: false, dark: false);
          if (owner != null) expect(_messageOwner(t, kind), same(owner));
        },
      );
    }
    for (final fails in [false, true]) {
      _case(kind, 'dispose-before-ready-${fails ? 'error' : 'success'}', (
        t,
        transport,
      ) async {
        await transport.push(
          t,
          transport.snapshot(
            opening: 2,
            revision: 2,
            suite: InteractionSuite.glow,
            reduce: true,
            dark: true,
          ),
        );
        _presentation(t, InteractionSuite.glow, reduce: true, dark: true);
        await t.pumpWidget(const SizedBox());
        await _frames(t);
        final callsAfterDispose = transport.calls.length;
        final paintedAfterDispose = transport.painted;
        expect(transport.readyReturned, false);
        if (fails) {
          transport.ready.completeError(
            PlatformException(code: 'fixture.late-ready'),
          );
        } else {
          transport.ready.complete(
            transport.snapshot(
              opening: 1,
              revision: 1,
              suite: InteractionSuite.rail,
              reduce: false,
              dark: false,
            ),
          );
        }
        await _frames(t);
        expect(transport.readyReturned, true);
        expect(find.byType(Scaffold), findsNothing);
        expect(transport.calls, hasLength(callsAfterDispose));
        expect(transport.painted, paintedAfterDispose);
        expect(t.hasRunningAnimations, false);
      });
    }
  }
}
