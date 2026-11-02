import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/shared/release/official_client_profile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/friends_window/friends_window_app_test.dart' as friends;
import '../../app/social_windows/social_window_test.dart' show native;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

const _channel = MethodChannel('starbridge/friends-surface');
const _failure = '操作未确认，请刷新列表核对后再试。';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Object _error(String kind) => kind == 'platform'
    ? PlatformException(code: 'fixture.ready')
    : MissingPluginException('fixture.ready');

void main() {
  setUpAll(loadFonts);

  for (final kind in ['platform', 'plugin']) {
    testWidgets('initial ready failure remains visible: $kind', (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final ready = Completer<Object?>();
      final calls = <MethodCall>[];
      size(tester, const Size(392, 720));
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'ready') return ready.future;
        fail('Unexpected native call: ${call.method}');
      });
      try {
        await tester.pumpWidget(const FriendsWindowApp());
        await _frames(tester);
        expect(calls.map((c) => c.method), ['ready']);
        expect(find.text(_failure), findsNothing);
        ready.completeError(_error(kind));
        await _frames(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(_failure), findsOneWidget);
        expect(calls.map((c) => c.method), ['ready']);
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (!ready.isCompleted) ready.complete(null);
        await _frames(tester);
        messenger.setMockMethodCallHandler(_channel, null);
      }
    });
  }

  for (final kind in ['platform', 'plugin']) {
    testWidgets(
      'valid friends snapshot is not failed by older pending ready error: $kind',
      (tester) async {
        final messenger = tester.binding.defaultBinaryMessenger;
        final ready = Completer<Object?>();
        final calls = <MethodCall>[];
        var readyReturned = false;
        size(tester, const Size(392, 720));
        messenger.setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'ready') {
            try {
              return await ready.future;
            } finally {
              readyReturned = true;
            }
          }
          if (call.method == 'painted') return null;
          fail('Unexpected native call: ${call.method}');
        });
        try {
          await tester.pumpWidget(const FriendsWindowApp());
          await _frames(tester);
          expect(calls.where((c) => c.method == 'ready'), hasLength(1));
          expect(ready.isCompleted, isFalse);
          await native(_channel.name, 'snapshot', {
            ...friends.snapshot(opening: 2, revision: 3),
            'presentation': {
              'appearanceMode': 'dark',
              'locale': 'zh-CN',
              'interactionStyle': 'glow',
              'reduceMotion': true,
            },
          });
          await _frames(tester);
          expect(find.text(_failure), findsNothing);
          final scaffold = tester.element(find.byType(Scaffold));
          expect(InteractionScope.of(scaffold).suite, InteractionSuite.glow);
          expect(InteractionScope.of(scaffold).reduceMotion, isTrue);
          final painted = calls.where((c) => c.method == 'painted').length;
          expect(painted, greaterThan(0));

          ready.completeError(_error(kind));
          await _frames(tester);
          expect(readyReturned, isTrue);
          expect(tester.takeException(), isNull);
          expect(tester.element(find.byType(Scaffold)), same(scaffold));
          expect(InteractionScope.of(scaffold).suite, InteractionSuite.glow);
          expect(InteractionScope.of(scaffold).reduceMotion, isTrue);
          expect(calls.where((c) => c.method == 'painted'), hasLength(painted));
          expect(calls.where((c) => c.method == 'ready'), hasLength(1));
          expect(
            calls.where((c) => !const {'ready', 'painted'}.contains(c.method)),
            isEmpty,
          );
          expect(
            find.text(_failure),
            findsNothing,
            reason: 'A valid pushed snapshot supersedes startup ready failure.',
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (!ready.isCompleted) ready.complete(null);
          await _frames(tester);
          messenger.setMockMethodCallHandler(_channel, null);
        }
      },
      skip: !OfficialClientProfile.advancedInteractions,
    );
  }
}
