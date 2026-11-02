import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/friends_window/friends_window_app_test.dart' show snapshot;
import '../../app/tray_surface_test.dart' show native;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cx_actions_test.dart' show fire;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader', 'ime']) {
      for (final result in ['accepted', 'refused', 'error']) {
        testWidgets(
          '$suite $input $result actual detached friend search retains transport owner',
          (t) async {
            const channel = MethodChannel('starbridge/friends-surface');
            final calls = <MethodCall>[];
            final pending = Completer<bool>();
            final semantics = t.ensureSemantics();
            final initial = {
              ...snapshot(),
              'presentation': {
                'appearanceMode': 'dark',
                'locale': 'zh-CN',
                'interactionStyle': suite.name,
              },
            };
            t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
              call,
            ) async {
              calls.add(call);
              if (call.method == 'ready') return initial;
              if (call.method == 'action') return pending.future;
              return null;
            });
            try {
              size(t, const Size(600, 900));
              await t.pumpWidget(const FriendsWindowApp());
              await t.pumpAndSettle();
              final field = find.byKey(
                const ValueKey('friends-account-search'),
              );
              await t.enterText(field, 'Alpha');
              await t.pump();
              final controller = t.widget<TextField>(field).controller!;
              expect(calls.where((c) => c.method == 'action'), isEmpty);
              if (input == 'ime') {
                await t.testTextInput.receiveAction(TextInputAction.search);
              } else {
                await fire(
                  t,
                  input,
                  find.byKey(const ValueKey('friends-search')),
                );
              }
              await t.pump();
              final actions = calls.where((c) => c.method == 'action').toList();
              expect(actions, hasLength(1));
              expect(actions.single.arguments, {
                'opening': 1,
                'revision': 1,
                'scope': 'friends1',
                'action': 'search',
                'key': '',
                'value': 'Alpha',
                'motionSource': input == 'pointer' ? 'pointer' : 'keyboard',
              });
              await t.tapAt(
                t.getCenter(find.byKey(const ValueKey('friends-search'))),
              );
              await t.pump();
              expect(calls.where((c) => c.method == 'action'), hasLength(1));
              if (result == 'error') {
                pending.completeError(
                  PlatformException(code: 'synthetic-rejection'),
                );
              } else {
                pending.complete(result == 'accepted');
              }
              await t.pumpAndSettle();
              expect(
                find.text('操作未确认，请刷新列表核对后再试。'),
                result == 'accepted' ? findsNothing : findsOneWidget,
              );
              expect(t.widget<TextField>(field).controller, same(controller));
              expect(controller.text, 'Alpha');
              expect(calls.where((c) => c.method == 'action'), hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              if (!pending.isCompleted) pending.complete(false);
              await t.pumpWidget(const SizedBox());
              await t.pump();
              t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                channel,
                null,
              );
              semantics.dispose();
            }
          },
        );
      }
    }
    for (final boundary in ['scope', 'disposed']) {
      testWidgets(
        '$suite actual detached query $boundary retires editor or late UI',
        (t) async {
          const channel = MethodChannel('starbridge/friends-surface');
          final calls = <MethodCall>[];
          final pending = Completer<bool>();
          Map<String, Object?> payload(int opening, int revision) => {
            ...snapshot(opening: opening, revision: revision),
            'presentation': {
              'appearanceMode': 'dark',
              'locale': 'zh-CN',
              'interactionStyle': suite.name,
              'reduceMotion': true,
            },
          };
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'ready') return payload(1, 1);
            if (call.method == 'action') return pending.future;
            return null;
          });
          try {
            size(t, const Size(600, 900));
            await t.pumpWidget(const FriendsWindowApp());
            await t.pumpAndSettle();
            final field = find.byKey(const ValueKey('friends-account-search'));
            await t.enterText(field, 'PrivateDraft');
            final oldController = t.widget<TextField>(field).controller;
            if (boundary == 'scope') {
              await native(t.binding, channel.name, 'snapshot', payload(2, 2));
              await t.pump();
              await t.pump();
              expect(
                t.widget<TextField>(field).controller,
                isNot(same(oldController)),
              );
              expect(t.widget<TextField>(field).controller!.text, isEmpty);
              await native(t.binding, channel.name, 'snapshot', payload(1, 1));
              await t.pump();
              await t.pump();
              expect(t.widget<TextField>(field).controller!.text, isEmpty);
              expect(calls.where((c) => c.method == 'action'), isEmpty);
            } else {
              await t.testTextInput.receiveAction(TextInputAction.search);
              await t.pump();
              expect(calls.where((c) => c.method == 'action'), hasLength(1));
              await t.pumpWidget(const SizedBox());
              pending.completeError(
                PlatformException(code: 'synthetic-late-rejection'),
              );
              await t.pump();
              await t.pump();
              expect(find.byType(FriendsWindowApp), findsNothing);
            }
            expect(t.takeException(), isNull);
          } finally {
            if (!pending.isCompleted) pending.complete(false);
            await t.pumpWidget(const SizedBox());
            await t.pump();
            t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              channel,
              null,
            );
          }
        },
      );
    }
  }
}
