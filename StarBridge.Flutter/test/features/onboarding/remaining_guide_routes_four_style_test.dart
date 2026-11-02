import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/onboarding/local_history_controller.dart';
import 'package:starbridge_flutter/features/onboarding/local_history_panel.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_flutter/features/onboarding/online_restore_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp, keyPress;
import 'local_history_test.dart' show FakeHistoryPort;
import 'onboarding_test_support.dart' show FakeOnboardingPort, facts;
import 'online_restore_dialog_test.dart' show InstallationPort, receipt;
import 'online_review_test_support.dart'
    show FakeOnlinePort, reviewWire, onlineWire;

void expectRoute(WidgetTester t, InteractionSuite suite, bool reduce) {
  final context = t.element(find.byType(AlertDialog));
  final route = ModalRoute.of(context)!;
  expect(route, isA<StarBridgeDialogRoute<bool>>());
  expect(InteractionScope.of(context).suite, suite);
  if (reduce) expect(route.animation!.value, 1);
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final reduce in [false, true]) {
      for (final success in [false, true]) {
        testWidgets(
          '${suite.name} reduce=$reduce restore async success=$success preserves newer draft',
          (t) async {
            final review = FakeOnlinePort()
              ..snapshot = OnlineReviewWire.parse(reviewWire(confirmed: true));
            final installation = InstallationPort();
            final cancel = Completer<OnlineReviewSnapshot>();
            final installed = Completer<bool>();
            review.onAction = (_) => cancel.future;
            late BuildContext root;
            Future<bool>? completion;
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) {
                    root = context;
                    return const SizedBox();
                  },
                ),
                suite,
                reduce: reduce,
              ),
            );
            await t.pumpAndSettle();
            completion = showOnlineRestoreDialog(
              root,
              review: review,
              installation: installation,
              onInstalled: () => installed.future,
            );
            await t.pumpAndSettle();
            if (success) {
              await t.tap(find.byKey(const Key('online-restore-install')));
              installation.pending.complete(receipt('online'));
              await t.pump();
            } else {
              await t.tap(find.byKey(const Key('online-restore-close')));
              await t.pump();
              expect(review.actions, [OnlineReviewAction.cancel]);
            }
            final draft = TextEditingController(text: 'keep draft');
            unawaited(
              showDialog<void>(
                context: root,
                builder: (_) =>
                    AlertDialog(content: TextField(controller: draft)),
              ),
            );
            await t.pumpAndSettle();
            if (success) {
              installed.complete(true);
            } else {
              cancel.complete(
                OnlineReviewWire.parse(
                  onlineWire(mode: 'local', state: 'notStarted', revision: 4),
                ),
              );
            }
            await t.pumpAndSettle();
            expect(await completion, success);
            expect(find.byType(TextField), findsOneWidget);
            expect(draft.text, 'keep draft');
            expect(find.byKey(const Key('online-restore-close')), findsNothing);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            draft.dispose();
            await review.close();
          },
        );
      }
      testWidgets('${suite.name} reduce=$reduce failed-save confirmation', (
        t,
      ) async {
        final port = FakeOnboardingPort(facts())..saveReceipt = false;
        final c = OnboardingController(port);
        var closes = 0;
        await t.pumpWidget(
          scopedApp(
            OnboardingPage(controller: c, onClose: () => closes++),
            suite,
            reduce: reduce,
          ),
        );
        await t.pumpAndSettle();
        await keyPress(t, find.byKey(const Key('onboarding-close')));
        await t.pumpAndSettle();
        expectRoute(t, suite, reduce);
        expect(
          ModalRoute.of(t.element(find.byType(AlertDialog)))!.animation!.value,
          1,
        );
        await keyPress(t, find.widgetWithText(StarBridgeActionButton, '继续设置'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(closes, 0);
        await t.pumpWidget(const SizedBox());
        c.dispose();
      });
      testWidgets(
        '${suite.name} reduce=$reduce history confirmation does not reset on cancel',
        (t) async {
          final port = FakeHistoryPort();
          final c = LocalHistoryController(port);
          await t.pumpWidget(
            scopedApp(
              SingleChildScrollView(
                child: LocalHistoryPanel(
                  copy: OnboardingCopy(const Locale('zh', 'CN')),
                  controller: c,
                  enabled: true,
                ),
              ),
              suite,
              reduce: reduce,
            ),
          );
          await t.pumpAndSettle();
          await keyPress(t, find.byKey(const Key('history-reset')));
          await t.pumpAndSettle();
          expectRoute(t, suite, reduce);
          expect(port.resetPreviews, 1);
          await keyPress(t, find.byKey(const Key('history-reset-keep')));
          expect(find.byType(AlertDialog), findsNothing);
          expect(port.resetConfirms, 0);
          await t.pumpWidget(const SizedBox());
          c.dispose();
          await port.events.close();
        },
      );
      testWidgets(
        '${suite.name} reduce=$reduce online restore keeps explicit install boundary',
        (t) async {
          late BuildContext entry;
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) {
                  entry = context;
                  return const SizedBox();
                },
              ),
              suite,
              reduce: reduce,
            ),
          );
          await t.pumpAndSettle();
          final review = FakeOnlinePort();
          final port = InstallationPort();
          final result = showOnlineRestoreDialog(
            entry,
            review: review,
            installation: port,
            onInstalled: () async => true,
          );
          await t.pumpAndSettle();
          expectRoute(t, suite, reduce);
          expect(
            ModalRoute.of(t.element(find.byType(AlertDialog)))!
                .barrierDismissible,
            isFalse,
          );
          expect(port.revisions, isEmpty);
          await keyPress(t, find.byKey(const Key('online-restore-close')));
          expect(find.byType(AlertDialog), findsNothing);
          expect(await result, isFalse);
          expect(port.revisions, isEmpty);
          await t.pumpWidget(const SizedBox());
          await review.close();
        },
      );
    }
  }
}
