import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_app.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/shared/release/official_client_profile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/social_windows/social_window_test.dart' show native;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

const _failure = '暂时无法完成操作，请重新打开窗口核对。';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(loadFonts);
  for (final kind in ['messages', 'notifications']) {
    testWidgets('initial ready failure remains visible: $kind', (tester) async {
      final channel = MethodChannel('starbridge/$kind-surface');
      final messenger = tester.binding.defaultBinaryMessenger;
      final ready = Completer<Object?>();
      final calls = <MethodCall>[];
      size(tester, const Size(1100, 850));
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'ready') return ready.future;
        fail('Unexpected native call: ${call.method}');
      });
      try {
        await tester.pumpWidget(SocialWindowApp(kind: kind));
        await _frames(tester);
        expect(calls.map((c) => c.method), ['ready']);
        expect(find.text(_failure), findsNothing);
        ready.completeError(PlatformException(code: 'fixture.ready'));
        await _frames(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(_failure), findsOneWidget);
        expect(calls.map((c) => c.method), ['ready']);
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (!ready.isCompleted) ready.complete(null);
        await _frames(tester);
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    testWidgets(
      'valid social snapshot is not failed by older ready error: $kind',
      (tester) async {
        final channel = MethodChannel('starbridge/$kind-surface');
        final messenger = tester.binding.defaultBinaryMessenger;
        final ready = Completer<Object?>();
        final calls = <MethodCall>[];
        final unexpected = <String>[];
        var returned = false;
        size(tester, const Size(1100, 850));
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'ready') {
            try {
              return await ready.future;
            } finally {
              returned = true;
            }
          }
          if (call.method == 'painted' || call.method == 'layout') return null;
          if (call.method == 'rpc') {
            final op = (call.arguments as Map)['op'];
            if (op == 'directory') return <Object?>[];
            if (op == 'refresh') return {'items': <Object?>[], 'ready': true};
            if (op == 'viewport') return true;
            unexpected.add('rpc:$op');
          } else {
            unexpected.add(call.method);
          }
          fail('Unexpected native call: ${unexpected.last}');
        });
        try {
          await tester.pumpWidget(SocialWindowApp(kind: kind));
          await _frames(tester);
          expect(calls.where((c) => c.method == 'ready'), hasLength(1));
          expect(ready.isCompleted, isFalse);
          await native(channel.name, 'snapshot', {
            'opening': 2,
            'revision': 3,
            'openingSource': 'keyboard',
            'view': jsonEncode({
              'scope': 'ready-error-$kind',
              'targetVersion': 0,
            }),
            'presentation': {
              'appearanceMode': 'dark',
              'locale': 'zh-CN',
              'interactionStyle': 'scan',
              'reduceMotion': true,
            },
          });
          await _frames(tester);
          expect(find.text(_failure), findsNothing);
          final scaffold = tester.element(find.byType(Scaffold));
          final owner = kind == 'messages'
              ? tester
                    .widget<DirectMessagesPage>(find.byType(DirectMessagesPage))
                    .sharedModule
              : tester
                    .widget<NotificationInboxPage>(
                      find.byType(NotificationInboxPage),
                    )
                    .controller;
          final painted = calls.where((c) => c.method == 'painted').length;
          expect(painted, greaterThan(0));
          expect(InteractionScope.of(scaffold).suite, InteractionSuite.scan);
          expect(InteractionScope.of(scaffold).reduceMotion, isTrue);
          ready.completeError(PlatformException(code: 'fixture.late-ready'));
          await _frames(tester);
          expect(returned, isTrue);
          expect(tester.takeException(), isNull);
          expect(tester.element(find.byType(Scaffold)), same(scaffold));
          expect(InteractionScope.of(scaffold).suite, InteractionSuite.scan);
          expect(InteractionScope.of(scaffold).reduceMotion, isTrue);
          if (kind == 'messages') {
            expect(
              tester
                  .widget<DirectMessagesPage>(find.byType(DirectMessagesPage))
                  .sharedModule,
              same(owner),
            );
          } else {
            expect(
              tester
                  .widget<NotificationInboxPage>(
                    find.byType(NotificationInboxPage),
                  )
                  .controller,
              same(owner),
            );
          }
          expect(calls.where((c) => c.method == 'painted'), hasLength(painted));
          expect(calls.where((c) => c.method == 'ready'), hasLength(1));
          expect(unexpected, isEmpty);
          expect(
            find.text(_failure),
            findsNothing,
            reason: 'A valid social snapshot supersedes startup ready failure.',
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (!ready.isCompleted) ready.complete(null);
          await _frames(tester);
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
      skip: !OfficialClientProfile.advancedInteractions,
    );
  }
}
