import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_channels.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';

import 'interaction_batch3ae_test.dart' show mount;
import '../../features/friends/social_layout_test.dart' show loadFonts;

FocusNode _owner(WidgetTester t, Finder target) {
  expect(target, findsOneWidget);
  expect(t.widget(target), isA<SuitePressable>());
  final detector = find.descendant(
    of: target,
    matching: find.byType(FocusableActionDetector),
  );
  expect(detector, findsOneWidget);
  return t.widget<FocusableActionDetector>(detector).focusNode!;
}

Future<void> _frames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

Future<void> _tabTo(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await _frames(t);
  final owner = _owner(t, target);
  expect(owner.canRequestFocus, isTrue);
  for (var i = 0; i < 12 && !owner.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await _frames(t);
  }
  expect(owner.hasPrimaryFocus, isTrue);
  expect(FocusManager.instance.primaryFocus, same(owner));
}

void _onlyPreviewChanged(
  NotificationSettingsValue next,
  NotificationSettingsValue original,
) {
  expect(next.previewMode, NotificationPreviewMode.hiddenDetails);
  expect(next.localInAppOnly, original.localInAppOnly);
  expect(next.desktopDeliveryAvailable, original.desktopDeliveryAvailable);
  expect(
    next.directMessageDeliveryAvailable,
    original.directMessageDeliveryAvailable,
  );
  expect(next.overlayDeliveryAvailable, original.overlayDeliveryAvailable);
  expect(next.channels, same(original.channels));
  expect(next.sourceRules, orderedEquals(original.sourceRules));
  expect(next.playerActivity, same(original.playerActivity));
  expect(next.continuousPlay, same(original.continuousPlay));
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final width in [430.0, 1100.0]) {
      testWidgets(
        '$suite preview actual Tab Enter at $width preserves exact payload and selected no-repeat',
        (t) async {
          final semantics = t.ensureSemantics();
          final snapshot =
              InMemoryNotificationSettingsAdapter.forReview().current;
          final original = snapshot.settings!;
          var value = original;
          final payloads = <NotificationSettingsValue>[];
          final sources = <InteractionSource>[];
          try {
            await mount(
              t,
              StatefulBuilder(
                builder: (context, update) => SingleChildScrollView(
                  child: NotificationPreviewPanel(
                    settings: value,
                    enabled: true,
                    onSave: (next) async {
                      sources.add(currentStarBridgeActivationSource);
                      payloads.add(next);
                      update(() => value = next);
                      return true;
                    },
                  ),
                ),
              ),
              suite,
              width: width,
            );
            final target = find.byKey(
              const Key('notification-preview-hiddenDetails'),
            );
            await _tabTo(t, target);
            expect(payloads, isEmpty);
            expect(value, same(original));
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
            await _frames(t);
            expect(payloads, hasLength(1));
            expect(sources, [InteractionSource.keyboard]);
            _onlyPreviewChanged(payloads.single, original);
            expect(value, same(payloads.single));
            expect(snapshot.settings, same(original));
            expect(snapshot.revision, 11);
            expect(
              t
                  .getSemantics(target)
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              Tristate.isTrue,
            );
            expect(_owner(t, target).hasPrimaryFocus, isTrue);
            // A selected option acknowledges activation without resubmitting.
            for (final key in [
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.space,
            ]) {
              await t.sendKeyEvent(key);
              await _frames(t);
              expect(payloads, hasLength(1));
              expect(sources, [InteractionSource.keyboard]);
            }
            for (final element
                in find
                    .descendant(of: target, matching: find.byType(EffectHost))
                    .evaluate()) {
              final host =
                  (element as StatefulElement).state as EffectHostState;
              for (final effect in TransientEffect.values) {
                expect(host.isPlaying(effect), isFalse);
              }
            }
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite disabled preview is skipped by actual Tab and exposes no reader activation',
      (t) async {
        final semantics = t.ensureSemantics();
        final before = FocusNode(), after = FocusNode();
        final snapshot =
            InMemoryNotificationSettingsAdapter.forReview().current;
        var calls = 0, sentinelCalls = 0;
        try {
          await mount(
            t,
            SingleChildScrollView(
              child: Column(
                children: [
                  TextButton(
                    focusNode: before,
                    onPressed: () => sentinelCalls++,
                    child: const Text('Before'),
                  ),
                  NotificationPreviewPanel(
                    settings: snapshot.settings!,
                    enabled: false,
                    onSave: (_) async {
                      calls++;
                      return true;
                    },
                  ),
                  TextButton(
                    focusNode: after,
                    onPressed: () => sentinelCalls++,
                    child: const Text('After'),
                  ),
                ],
              ),
            ),
            suite,
            width: 430,
          );
          final owners = <FocusNode>[];
          for (final mode in NotificationPreviewMode.values) {
            final target = find.byKey(Key('notification-preview-${mode.name}'));
            owners.add(_owner(t, target));
            expect(
              t
                  .getSemantics(target)
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isFalse,
            );
          }
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await _frames(t);
          expect(before.hasPrimaryFocus, isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await _frames(t);
          expect(
            after.hasPrimaryFocus,
            isTrue,
            reason: 'All three disabled choices must be skipped.',
          );
          expect(owners.every((node) => !node.hasPrimaryFocus), isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await _frames(t);
          expect(sentinelCalls, 1);
          expect(calls, 0);
          expect(snapshot.revision, 11);
          expect(
            snapshot.settings!.previewMode,
            NotificationPreviewMode.sourceOnly,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          before.dispose();
          after.dispose();
          semantics.dispose();
        }
      },
    );
  }
}
