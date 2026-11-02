import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';
import 'package:starbridge_flutter/features/settings/help_support_settings_page.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3dg_actions_test.dart' show HelpMotionPort;
import 'interaction_batch3dc_actions_test.dart' show hitRow;
import 'interaction_batch3i_test.dart' show scopedApp;

const editing = TextEditingValue(
  text: 'pending draft',
  selection: TextSelection(baseOffset: 2, extentOffset: 7),
  composing: TextRange(start: 1, end: 8),
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard']) {
      for (final within in [true, false]) {
        for (final success in [true, false]) {
          testWidgets(
            '$suite $input receipt success=$success within-original-exit=$within preserves native lifetime',
            (t) async {
              size(t, const Size(1400, 1100));
              final port = HelpMotionPort();
              await t.pumpWidget(
                scopedApp(
                  HelpSupportSettingsPage(
                    port: port,
                    initialTopic: HelpSupportTopic.feedback,
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              final message = t
                  .widget<TextField>(
                    find.byKey(const Key('help-feedback-message')),
                  )
                  .controller!;
              final contact = t
                  .widget<TextField>(
                    find.byKey(const Key('help-feedback-contact')),
                  )
                  .controller!;
              contact.text = ' fixture ';
              await t.enterText(
                find.byKey(const Key('help-feedback-message')),
                editing.text,
              );
              message.value = editing;
              await t.pump();
              final original = t.state(find.byType(HelpSupportFeedbackForm));
              await t.ensureVisible(
                find.byKey(const Key('help-feedback-send')),
              );
              await t.tap(find.byKey(const Key('help-feedback-send')));
              await t.pump();
              expect(port.drafts, [('fixture', editing.text)]);
              // The native disabled TextField finalizes IME composition when the
              // original owner enters busy. Preserve the resulting full value.
              final submitted = message.value;
              await hitRow(t, input, 'help-topic-button-notices');
              await t.pump();
              final outgoing = find.ancestor(
                of: find.byType(HelpSupportFeedbackForm),
                matching: find.byType(StarBridgePageTransition),
              );
              expect(original.mounted, isTrue);
              expect(
                t.widget<StarBridgePageTransition>(outgoing).animation.status,
                AnimationStatus.reverse,
              );
              final exclusion = find.ancestor(
                of: find.byType(HelpSupportFeedbackForm),
                matching: find.byWidgetPredicate(
                  (w) => w is IgnorePointer && w.ignoring,
                ),
              );
              expect(exclusion, findsWidgets);
              if (within) {
                await t.pump(const Duration(milliseconds: 30));
                expect(original.mounted, isTrue);
              } else {
                await t.pump(const Duration(milliseconds: 150));
                await t.pump();
                expect(original.mounted, isFalse);
              }
              if (success) {
                port.sends.single.complete();
              } else {
                port.sends.single.completeError(StateError('uncertain'));
              }
              await t.pump();
              if (within && success) {
                expect(message.text, isEmpty);
                expect(message.value.composing, TextRange.empty);
              } else {
                expect(message.value, submitted);
              }
              final receiptValue = message.value;
              await t.pumpAndSettle();
              await hitRow(t, input, 'help-topic-button-feedback');
              await t.pumpAndSettle();
              expect(
                t
                    .widget<TextField>(
                      find.byKey(const Key('help-feedback-message')),
                    )
                    .controller,
                same(message),
              );
              expect(message.value, receiptValue);
              expect(port.sends, hasLength(1));
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            },
          );
        }
      }
    }
    testWidgets(
      '$suite rapid leave-return has distinct retired views and no invisible input',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = HelpMotionPort();
        await t.pumpWidget(
          scopedApp(
            HelpSupportSettingsPage(
              port: port,
              initialTopic: HelpSupportTopic.feedback,
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('help-feedback-message')),
          'retained',
        );
        final old = t.state(find.byType(HelpSupportFeedbackForm));
        await hitRow(t, 'keyboard', 'help-topic-button-notices');
        await t.pump();
        await hitRow(t, 'pointer', 'help-topic-button-feedback');
        await t.pump();
        expect(find.byType(HelpSupportFeedbackForm), findsNWidgets(2));
        final entries = t.widgetList<StarBridgePageTransition>(
          find.byType(StarBridgePageTransition),
        );
        final leaving = entries
            .where((w) => w.animation.status == AnimationStatus.reverse)
            .toList();
        expect(leaving, isNotEmpty);
        expect(
          leaving.every((w) => w.instant),
          isTrue,
          reason: 'later pointer must not revive keyboard-hidden entries',
        );
        await t.pumpAndSettle();
        expect(old.mounted, isFalse);
        expect(find.byType(HelpSupportFeedbackForm), findsOneWidget);
        expect(
          t
              .widget<TextField>(find.byKey(const Key('help-feedback-message')))
              .controller!
              .text,
          'retained',
        );
        expect(port.sends, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
