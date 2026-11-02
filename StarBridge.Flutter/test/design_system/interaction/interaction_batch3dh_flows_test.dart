import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';
import 'package:starbridge_flutter/features/settings/help_support_feedback_content.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3dh_test.dart' show HelpPendingPort;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder get send => find.byKey(const Key('help-feedback-send'));
StarBridgeActionButton sendAction(WidgetTester t) =>
    t.widget<StarBridgeActionButton>(
      find.ancestor(of: send, matching: find.byType(StarBridgeActionButton)),
    );
const group = HelpSupportFeedbackContent(
  heading: SizedBox(),
  unavailableNotice: SizedBox(),
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final outcome in ['success', 'failure', 'disposed']) {
        testWidgets(
          '$suite $input send $outcome keeps original single-flight and real receipt',
          (t) async {
            size(t, const Size(1400, 1100));
            final sem = t.ensureSemantics();
            final port = HelpPendingPort();
            final message = TextEditingController(),
                contact = TextEditingController();
            try {
              await t.pumpWidget(
                scopedApp(
                  HelpSupportFeedbackForm(
                    port: port,
                    message: message,
                    contact: contact,
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              expect(port.sends, isEmpty);
              expect(sendAction(t).onActivate, isNull);
              await t.enterText(
                find.byKey(const Key('help-feedback-contact')),
                ' fixture@example ',
              );
              await t.enterText(
                find.byKey(const Key('help-feedback-message')),
                ' payload ',
              );
              await t.pump();
              final staleCallback = sendAction(t).onActivate!;
              await fire(t, input, 'help-feedback-send');
              staleCallback(
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              await t.pump();
              await t.pump();
              expect(port.sends, hasLength(1));
              expect(port.sends.single.$1, 'fixture@example');
              expect(port.sends.single.$2, 'payload');
              expect(sendAction(t).onActivate, isNull);
              for (final field in t.widgetList<TextField>(
                find.byType(TextField),
              )) {
                expect(field.enabled, isFalse);
              }
              for (final frame in t.widgetList<StarBridgeFieldFrame>(
                find.byType(StarBridgeFieldFrame),
              )) {
                expect(frame.enabled, isFalse);
              }
              expect(
                find.byType(SuiteProgressBar),
                input == 'pointer' ? findsOneWidget : findsNothing,
              );
              expect(find.text('反馈已发送，谢谢。'), findsNothing);
              final busyValue = message.value;
              await t.pump(const Duration(seconds: 30));
              expect(port.sends, hasLength(1));
              expect(
                message.value,
                busyValue,
                reason: 'send has no new artificial timeout',
              );
              if (outcome == 'disposed') await t.pumpWidget(const SizedBox());
              if (outcome == 'failure') {
                port.sends.single.$3.completeError(StateError('uncertain'));
              } else {
                port.sends.single.$3.complete();
              }
              await t.pumpAndSettle();
              if (outcome == 'success') {
                expect(message.text, isEmpty);
                expect(find.text('反馈已发送，谢谢。'), findsOneWidget);
              } else {
                expect(message.value, busyValue);
                if (outcome == 'failure') {
                  expect(find.textContaining('内容已保留'), findsOneWidget);
                }
              }
              expect(port.sends, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              for (final call in port.sends) {
                if (!call.$3.isCompleted) call.$3.complete();
              }
              await t.pumpWidget(const SizedBox());
              await t.pump();
              message.dispose();
              contact.dispose();
              sem.dispose();
            }
          },
        );
      }
      testWidgets(
        '$suite $input copy group waits for platform success and preserves messenger queue order',
        (t) async {
          size(t, const Size(1400, 1100));
          final sem = t.ensureSemantics();
          final pending = Completer<void>();
          final copied = <String>[];
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied.add((call.arguments as Map)['text'] as String);
                await pending.future;
              }
              return null;
            },
          );
          try {
            await t.pumpWidget(scopedApp(group, suite));
            await t.pumpAndSettle();
            final messenger = ScaffoldMessenger.of(
              t.element(find.byType(HelpSupportFeedbackContent)),
            );
            final old = messenger.showSnackBar(
              const SnackBar(content: Text('previous')),
            );
            await t.pumpAndSettle();
            await fire(t, input, 'help-copy-feedback-group');
            await t.pump();
            expect(copied, ['534268220']);
            expect(find.text('previous'), findsOneWidget);
            pending.complete();
            await t.pumpAndSettle();
            expect(await old.closed, SnackBarClosedReason.hide);
            expect(find.text('previous'), findsNothing);
            expect(find.byType(SnackBar), findsOneWidget);
            expect(copied, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            if (!pending.isCompleted) pending.complete();
            await t.pumpWidget(const SizedBox());
            await t.pump();
            sem.dispose();
            t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            );
          }
        },
      );
    }
    testWidgets(
      '$suite editor values, IME and focus survive live suite/reduce changes',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = HelpPendingPort();
        final message = TextEditingController(),
            contact = TextEditingController();
        final settings = ValueNotifier((suite, false));
        try {
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder<(InteractionSuite, bool)>(
                valueListenable: settings,
                builder: (_, value, _) => StarBridgeInteractionConfiguration(
                  suite: value.$1,
                  reduceMotion: value.$2,
                  child: HelpSupportFeedbackForm(
                    port: port,
                    message: message,
                    contact: contact,
                  ),
                ),
              ),
              InteractionSuite.standard,
            ),
          );
          await t.pumpAndSettle();
          final target = find.byKey(const Key('help-feedback-message'));
          await t.tap(target);
          await t.pump();
          message.value = const TextEditingValue(
            text: 'kept IME',
            selection: TextSelection(baseOffset: 1, extentOffset: 5),
            composing: TextRange(start: 1, end: 6),
          );
          await t.pump();
          final value = message.value;
          final native = t.state(
            find.descendant(of: target, matching: find.byType(EditableText)),
          );
          final focus = t.widget<TextField>(target).focusNode!;
          for (final next in InteractionSuite.values) {
            settings.value = (next, true);
            await t.pump();
            await t.pump();
            expect(message.value, value);
            expect(
              t.state(
                find.descendant(
                  of: target,
                  matching: find.byType(EditableText),
                ),
              ),
              same(native),
            );
            expect(t.widget<TextField>(target).focusNode, same(focus));
            expect(focus.hasFocus, isTrue);
          }
          final field = t.widget<TextField>(target);
          expect(field.maxLength, 2000);
          expect(field.minLines, 4);
          expect(field.maxLines, 8);
          expect(field.onSubmitted, isNull);
          expect(
            t
                .widget<TextField>(
                  find.byKey(const Key('help-feedback-contact')),
                )
                .maxLength,
            120,
          );
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pump();
          expect(port.sends, isEmpty);
        } finally {
          await t.pumpWidget(const SizedBox());
          message.dispose();
          contact.dispose();
          settings.dispose();
        }
      },
    );
    testWidgets('$suite no port or whitespace never becomes a send action', (
      t,
    ) async {
      size(t, const Size(1400, 1100));
      final message = TextEditingController(),
          contact = TextEditingController();
      final port = HelpPendingPort();
      try {
        await t.pumpWidget(
          scopedApp(
            HelpSupportFeedbackForm(message: message, contact: contact),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('help-feedback-message')),
          'draft',
        );
        await t.pump();
        expect(sendAction(t).onActivate, isNull);
        await t.pumpWidget(
          scopedApp(
            HelpSupportFeedbackForm(
              port: port,
              message: message,
              contact: contact,
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('help-feedback-message')),
          '  \n ',
        );
        await t.pump();
        expect(sendAction(t).onActivate, isNull);
        expect(port.sends, isEmpty);
      } finally {
        await t.pumpWidget(const SizedBox());
        message.dispose();
        contact.dispose();
      }
    });
    for (final result in ['error', 'disposed']) {
      testWidgets('$suite copy $result never paints unconfirmed success', (
        t,
      ) async {
        size(t, const Size(1400, 1100));
        final pending = Completer<void>();
        final copied = <String>[];
        final errors = <Object>[];
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
              await pending.future;
              if (result == 'error') {
                throw PlatformException(code: 'fixture unavailable');
              }
            }
            return null;
          },
        );
        try {
          await t.pumpWidget(scopedApp(group, suite));
          await t.pumpAndSettle();
          // Invoke the exact feature callback inside an error-observing zone;
          // the original clipboard failure intentionally propagates outward.
          final feature = t.widget<HelpSupportAction>(
            find.ancestor(
              of: find.byKey(const Key('help-copy-feedback-group')),
              matching: find.byType(HelpSupportAction),
            ),
          );
          runZonedGuarded(
            () => feature.onActivate!(InteractionSource.pointer),
            (error, _) => errors.add(error),
          );
          await t.pump();
          expect(copied, ['534268220']);
          if (result == 'disposed') {
            await t.pumpWidget(const SizedBox());
          }
          pending.complete();
          await t.pump();
          await t.pump();
          expect(find.byType(SnackBar), findsNothing);
          expect(errors, result == 'error' ? hasLength(1) : isEmpty);
          if (errors.isNotEmpty) {
            expect(errors.single, isA<PlatformException>());
          }
        } finally {
          if (!pending.isCompleted) pending.complete();
          await t.pumpWidget(const SizedBox());
          await t.pump();
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        }
      });
    }
  }
}
