import 'dart:async';
import 'dart:ui' show CheckedState, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/runtime/usage_terms_page.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';

import '../features/settings/local_privacy_page_test.dart' show app, viewport;

void main() {
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets(
      'terms ${suite.name} consent preserves explicit gated choice and input paths',
      (tester) async {
        viewport(tester, const Size(800, 900));
        final semantics = tester.ensureSemantics();
        try {
          var accepts = 0;
          Widget surface(bool saving, {bool exiting = false}) => app(
            StarBridgeInteractionConfiguration(
              suite: suite,
              child: UsageTermsPage(
                saving: saving,
                exiting: exiting,
                failed: false,
                savingSource: InteractionSource.keyboard,
                readLicense: () async => const ClientLicenseDocument(
                  ClientLicenseState.ready,
                  'Synthetic complete license; no real acknowledgement is stored.',
                ),
                onAccept: () => accepts++,
                onExit: (_) {},
              ),
            ),
          );
          await tester.pumpWidget(surface(false));
          await tester.pumpAndSettle();
          final consent = find.byKey(const Key('usage-terms-consent'));
          final label = find.text('我已阅读并同意上述条款与声明');
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isChecked,
            CheckedState.isFalse,
          );
          Focus.of(tester.element(find.byKey(const Key('usage-terms-scroll'))))
              .requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.end);
          await tester.pumpAndSettle();
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isTrue,
          );
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isChecked,
            CheckedState.isFalse,
          );
          expect(
            tester.getRect(consent),
            const Rect.fromLTRB(20, 790, 780, 846),
          );
          expect(tester.getRect(label), const Rect.fromLTRB(76, 806, 780, 830));
          final face = find.descendant(
            of: consent,
            matching: find.byType(SuiteCheckbox),
          );
          expect(
            face,
            findsOneWidget,
            reason: 'Consent must visibly participate in the selected checkbox suite.',
          );
          await tester.tap(label);
          await tester.pump();
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isChecked,
            CheckedState.isTrue,
          );
          expect(accepts, 0);
          await tester.pumpWidget(surface(true));
          await tester.pump();
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isChecked,
            CheckedState.isTrue,
          );
          await tester.tap(consent, warnIfMissed: false);
          await tester.pump();
          expect(accepts, 0);
          await tester.pumpWidget(surface(false, exiting: true));
          await tester.pump();
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          await tester.pumpWidget(surface(false));
          await tester.pumpAndSettle();
          tester.widget<SuiteCheckbox>(face).focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isChecked,
            CheckedState.isFalse,
          );
          final node = tester.getSemantics(consent);
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(
            tester
                .getSemantics(consent)
                .getSemanticsData()
                .flagsCollection
                .isChecked,
            CheckedState.isTrue,
          );
          expect(accepts, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('terms reread uses the selected suite and keeps read ownership', (
    tester,
  ) async {
    viewport(tester, const Size(800, 900));
    var reads = 0, accepts = 0, exits = 0;
    final retry = Completer<ClientLicenseDocument>();
    await tester.pumpWidget(
      app(
        StarBridgeInteractionConfiguration(
          suite: InteractionSuite.scan,
          child: UsageTermsPage(
            saving: false,
            failed: false,
            savingSource: InteractionSource.pointer,
            readLicense: () {
              reads++;
              return reads == 1
                  ? Future.value(
                      const ClientLicenseDocument(
                        ClientLicenseState.unavailable,
                      ),
                    )
                  : retry.future;
            },
            onAccept: () => accepts++,
            onExit: (_) => exits++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('usage-terms-scroll')),
    );
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final reread = find.text('重新读取');
    expect(reread, findsOneWidget);
    expect(
      find.ancestor(of: reread, matching: find.byType(SuitePressable)),
      findsOneWidget,
      reason:
          'Reread must visibly participate in the selected interaction suite.',
    );
    await tester.tap(reread);
    await tester.pump();
    expect(reads, 2);
    expect(find.text('正在读取完整许可…'), findsOneWidget);
    expect(accepts, 0);
    expect(exits, 0);
    retry.complete(
      const ClientLicenseDocument(
        ClientLicenseState.ready,
        'Synthetic complete license; no real acknowledgement is stored.',
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(accepts, 0);
    expect(exits, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
