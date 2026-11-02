import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_flutter/features/onboarding/first_use_setup_entry.dart';
import 'package:starbridge_flutter/features/settings/help_support_port.dart';
import 'package:starbridge_flutter/features/settings/daily_support_port.dart';
import 'package:starbridge_flutter/features/settings/help_support_settings_page.dart';
import 'package:starbridge_flutter/features/settings/help_support_topic_transition.dart';
import 'package:starbridge_flutter/features/settings/settings_entry_dialog.dart';
import 'package:starbridge_flutter/shared/release/official_client_profile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/settings/daily_support_test.dart'
    show FakeSupport, thanks;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3dc_actions_test.dart' show hitRow;
import 'interaction_batch3i_test.dart' show scopedApp;

class HelpMotionPort implements HelpSupportPort {
  final browser = <Completer<Map<String, dynamic>>>[];
  final origins = <InteractionSource>[];
  final sends = <Completer<void>>[];
  final drafts = <(String, String)>[];
  @override
  Future<Map<String, dynamic>> read(String name) {
    if (name != 'helpSupport.openScm') {
      return Future.error(StateError('unavailable'));
    }
    origins.add(currentStarBridgeActivationSource);
    final reply = Completer<Map<String, dynamic>>();
    browser.add(reply);
    return reply.future;
  }

  @override
  Future<void> send(String contact, String message) {
    drafts.add((contact, message));
    final reply = Completer<void>();
    sends.add(reply);
    return reply.future;
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final connected in [false, true]) {
      testWidgets(
        '$suite connected=$connected local dialog buttons follow a different root theme',
        (t) async {
          size(t, const Size(1400, 1100));
          final settings = ValueNotifier((suite, false));
          final port = FakeSupport();
          try {
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder<(InteractionSuite, bool)>(
                  valueListenable: settings,
                  builder: (_, value, _) => StarBridgeInteractionConfiguration(
                    suite: value.$1,
                    reduceMotion: value.$2,
                    child: HelpSupportSettingsPage(
                      dailySupport: connected ? port : null,
                    ),
                  ),
                ),
                InteractionSuite.standard,
              ),
            );
            await t.pumpAndSettle();
            await fire(t, 'pointer', 'help-spiritual-support');
            await t.pumpAndSettle();
            final id = connected
                ? 'help-support-claim'
                : 'help-support-local-close';
            InteractionData actual() =>
                InteractionScope.of(t.element(find.byKey(Key(id))));
            expect(actual().suite, suite);
            final next = suite == InteractionSuite.glow
                ? InteractionSuite.rail
                : InteractionSuite.glow;
            settings.value = (next, true);
            await t.pump();
            await t.pump();
            expect(actual().suite, next);
            expect(actual().reduceMotion, isTrue);
            expect(port.claims, 0);
            expect(port.reads, 0);
          } finally {
            await t.pumpWidget(const SizedBox());
            await port.changed.close();
            settings.dispose();
          }
        },
      );
    }
    for (final finish in ['grant', 'account-change', 'closed']) {
      testWidgets(
        '$suite claim late receipt $finish retains original retirement',
        (t) async {
          size(t, const Size(1400, 1100));
          final port = FakeSupport();
          try {
            await t.pumpWidget(
              scopedApp(HelpSupportSettingsPage(dailySupport: port), suite),
            );
            await t.pumpAndSettle();
            await fire(t, 'pointer', 'help-spiritual-support');
            await t.pumpAndSettle();
            await fire(t, 'pointer', 'help-support-claim');
            await t.pump();
            expect(port.claims, 1);
            if (finish == 'account-change') {
              port.changed.add(null);
              await t.pumpAndSettle();
            }
            if (finish == 'closed') {
              await fire(t, 'keyboard', 'help-support-close');
              await t.pumpAndSettle();
            }
            port.pending.complete(
              DailySupportResult(
                'granted',
                entitlement: 'overlay.skin.night-shadow',
                expiresAt: DateTime.utc(2026, 11),
                localDay: '2026-10-15',
              ),
            );
            await t.pumpAndSettle();
            expect(
              find.text(thanks),
              finish == 'grant' ? findsOneWidget : findsNothing,
            );
            if (finish == 'account-change') {
              expect(find.textContaining('账号状态已变化'), findsOneWidget);
            }
            if (finish == 'closed') {
              expect(find.byType(AlertDialog), findsNothing);
            }
            expect(port.claims, 1);
            expect(port.reads, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await port.changed.close();
          }
        },
      );
    }
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input topic source and same-selection preserve draft',
        (t) async {
          size(t, const Size(1400, 1100));
          final semantics = t.ensureSemantics();
          try {
            await t.pumpWidget(
              scopedApp(const HelpSupportSettingsPage(), suite),
            );
            await t.pumpAndSettle();
            await hitRow(t, input, 'help-topic-button-feedback');
            await t.pump();
            final current = find.ancestor(
              of: find.byKey(const Key('help-topic-feedback')),
              matching: find.byType(StarBridgePageTransition),
            );
            final transition = t.widget<StarBridgePageTransition>(current);
            expect(transition.instant, input != 'pointer');
            await t.pumpAndSettle();
            final field = find.byKey(const Key('help-feedback-message'));
            await t.enterText(field, 'retained');
            final state = t.state(find.byType(HelpSupportTopicTransition).last);
            await hitRow(t, input, 'help-topic-button-feedback');
            await t.pump();
            expect(
              t.state(find.byType(HelpSupportTopicTransition).last),
              same(state),
            );
            expect(t.widget<TextField>(field).controller!.text, 'retained');
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $input SCM validates real receipt and preserves source',
        (t) async {
          size(t, const Size(1400, 1100));
          final sem = t.ensureSemantics();
          final port = HelpMotionPort();
          try {
            await t.pumpWidget(
              scopedApp(HelpSupportSettingsPage(port: port), suite),
            );
            await t.pumpAndSettle();
            expect(port.browser, isEmpty);
            await fire(t, input, 'help-scm-team');
            expect(port.origins, [
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            port.browser.single.complete({'schemaVersion': 1, 'opened': false});
            await t.pumpAndSettle();
            expect(find.byType(SnackBar), findsOneWidget);
            expect(port.browser, hasLength(1));
            await t.pump(const Duration(seconds: 5));
            await t.pumpAndSettle();
            await fire(t, input, 'help-scm-team');
            port.browser.last.complete({'schemaVersion': 1, 'opened': true});
            await t.pumpAndSettle();
            expect(find.byType(SnackBar), findsNothing);
            expect(port.browser, hasLength(2));
          } finally {
            await t.pumpWidget(const SizedBox());
            sem.dispose();
          }
        },
      );
      testWidgets(
        '$suite $input original setup and update callbacks receive source',
        (t) async {
          size(t, const Size(1400, 1100));
          final sem = t.ensureSemantics();
          final calls = <(String, InteractionSource)>[];
          try {
            await t.pumpWidget(
              scopedApp(
                FirstUseSetupEntry(
                  open: (_) async =>
                      calls.add(('setup', currentStarBridgeActivationSource)),
                  child: SettingsEntryOverrides(
                    openers: {
                      'application-updates': (_) async => calls.add((
                        'updates',
                        currentStarBridgeActivationSource,
                      )),
                    },
                    child: const HelpSupportSettingsPage(
                      initialTopic: HelpSupportTopic.updates,
                    ),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            // Developer profile intentionally retains the original first-use gate.
            expect(
              find.byKey(const Key('first-use-setup-entry')),
              OfficialClientProfile.firstUseGuide
                  ? findsOneWidget
                  : findsNothing,
            );
            if (OfficialClientProfile.firstUseGuide) {
              await fire(t, input, 'first-use-setup-entry');
              expect(calls.removeLast(), (
                'setup',
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ));
            }
            await fire(t, input, 'help-check-updates');
            expect(calls, [
              (
                'updates',
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
          } finally {
            await t.pumpWidget(const SizedBox());
            sem.dispose();
          }
        },
      );
      testWidgets(
        '$suite $input claim disclosure, unknown readback and close remain authoritative',
        (t) async {
          size(t, const Size(1400, 1100));
          final sem = t.ensureSemantics();
          final port = FakeSupport();
          try {
            await t.pumpWidget(
              scopedApp(HelpSupportSettingsPage(dailySupport: port), suite),
            );
            await t.pumpAndSettle();
            await fire(t, input, 'help-spiritual-support');
            await t.pumpAndSettle();
            final route =
                ModalRoute.of(t.element(find.byType(AlertDialog)))!
                    as StarBridgeDialogRoute<void>;
            expect(route.instant, input != 'pointer');
            expect(port.claims, 0);
            expect(port.reads, 0);
            expect(find.textContaining('含你用户名字'), findsOneWidget);
            await fire(t, input, 'help-support-claim');
            await t.pump();
            expect(port.claims, 1);
            expect(find.byKey(const Key('help-support-claim')), findsNothing);
            expect(find.text(thanks), findsNothing);
            port.pending.completeError(StateError('uncertain'));
            await t.pumpAndSettle();
            await fire(t, input, 'help-support-read-result');
            await t.pumpAndSettle();
            expect(port.claims, 1);
            expect(port.reads, 1);
            expect(find.text(thanks), findsNothing);
            await fire(t, input, 'help-support-close');
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
          } finally {
            await t.pumpWidget(const SizedBox());
            await port.changed.close();
            sem.dispose();
          }
        },
      );
    }
    for (final stage in ['entrance', 'settled']) {
      testWidgets(
        '$suite $stage local dialog follows reduced motion within two frames',
        (t) async {
          size(t, const Size(1400, 1100));
          final reduce = ValueNotifier(false);
          try {
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder<bool>(
                  valueListenable: reduce,
                  builder: (_, value, _) => StarBridgeInteractionConfiguration(
                    suite: suite,
                    reduceMotion: value,
                    child: const HelpSupportSettingsPage(),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await fire(t, 'pointer', 'help-spiritual-support');
            await t.pump();
            if (stage == 'settled') await t.pumpAndSettle();
            reduce.value = true;
            await t.pump();
            await t.pump();
            final route = ModalRoute.of(t.element(find.byType(AlertDialog)))!;
            expect(route.animation!.value, 1);
            expect(
              InteractionScope.of(
                t.element(find.byKey(const Key('help-support-local-close'))),
              ).reduceMotion,
              isTrue,
            );
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(route.animation!.value, 0);
            await t.pumpAndSettle();
          } finally {
            await t.pumpWidget(const SizedBox());
            reduce.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite SCM failure after disposal does not show a stale message',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = HelpMotionPort();
        await t.pumpWidget(
          scopedApp(HelpSupportSettingsPage(port: port), suite),
        );
        await t.pumpAndSettle();
        await fire(t, 'pointer', 'help-scm-team');
        await t.pumpWidget(const SizedBox());
        port.browser.single.completeError(StateError('late'));
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );
  }
}
