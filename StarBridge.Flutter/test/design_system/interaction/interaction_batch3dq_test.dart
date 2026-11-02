import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/first_use_privacy_dialog.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';

import 'interaction_batch3do_test.dart' as fixture;

final firstInitial = LocalPrivacySettings.editorDefaults.copyWith(
  fleetFields: 33,
  roomFields: 18,
  fleetAllMembersCanView: false,
  fleetAdministratorsCanView: true,
);

class FirstOutcome {
  bool done = false;
  bool? value;
  InteractionSource? source;
  StarBridgeDialogRoute<bool>? route;
}

class FirstProbe {
  final choices = <LocalPrivacySettings>[];
  final gate = Completer<bool>();
  FirstUsePrivacyDialog dialog() => FirstUsePrivacyDialog(
    initial: firstInitial,
    onSave: (choice) {
      choices.add(choice);
      return gate.future;
    },
  );
}

Widget firstApp(
  Widget dialog,
  InteractionSuite suite,
  FirstOutcome outcome, {
  bool light = false,
  bool reduce = false,
  double scale = 1,
  Locale locale = const Locale('zh', 'CN'),
}) {
  final base = fixture.scopedApp(
    Builder(
      builder: (context) => GestureDetector(
        onTap: () => runStarBridgeActivation<void>(
          InteractionSource.programmatic,
          () async {
            outcome.value = await showStarBridgeDialog<bool>(
              context,
              source: InteractionSource.programmatic,
              barrierDismissible: false,
              builder: (_) => dialog,
              onRouteCreated: (route) => outcome.route = route,
            );
            outcome.source = currentStarBridgeActivationSource;
            outcome.done = true;
          },
        ),
        child: const Text('Open first privacy'),
      ),
    ),
    suite,
    light: light,
    reduce: reduce,
    locale: locale,
  ) as MaterialApp;
  return RepaintBoundary(
    key: const Key('3dq-frame'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: base.locale,
      supportedLocales: base.supportedLocales,
      localizationsDelegates: base.localizationsDelegates,
      theme: base.theme,
      themeAnimationDuration: Duration.zero,
      home: base.home,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: base.builder!(context, child),
      ),
    ),
  );
}

Future<void> openFirst(
  WidgetTester t,
  Widget dialog,
  InteractionSuite suite,
  FirstOutcome outcome,
) async {
  await t.pumpWidget(firstApp(dialog, suite, outcome));
  await t.pumpAndSettle();
  await t.tap(find.text('Open first privacy'));
  await t.pumpAndSettle();
}

HelpSupportAction firstAction(WidgetTester t, String action) =>
    t.widget<HelpSupportAction>(
      find.byWidgetPredicate(
        (w) =>
            w is HelpSupportAction &&
            w.controlKey == Key('first-privacy-$action'),
      ),
    );
Future<void> activateFirst(WidgetTester t, String source, String action) =>
    fixture.act(
      t,
      find.byKey(Key('first-privacy-$action')),
      source,
      switch (action) {
        'accept' => '启用状态共享',
        'decline' => '暂不开启',
        _ => '调整共享范围',
      },
    );

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final accept in [true, false]) {
        testWidgets(
          '${suite.name}/$source/$accept pending obeys explicit choice and waits for acknowledgment',
          (t) async {
            fixture.size(t, const Size(960, 900));
            final semantics = t.ensureSemantics();
            try {
              final p = FirstProbe(), outcome = FirstOutcome();
              await openFirst(t, p.dialog(), suite, outcome);
              expect(p.choices, isEmpty);
              expect(find.byType(CheckboxListTile), findsNothing);
              final action = accept ? 'accept' : 'decline';
              final old = firstAction(t, action).onActivate!;
              await activateFirst(t, source, action);
              await t.pump();
              old(InteractionSource.pointer);
              expect(p.choices, hasLength(1));
              expect(
                p.choices.single.toJson(),
                firstInitial.copyWith(publicationEnabled: accept).toJson(),
              );
              for (final key in ['accept', 'decline', 'adjust']) {
                expect(firstAction(t, key).onActivate, isNull);
              }
              final wait = t.widget<HelpSupportWaiting>(
                find.byType(HelpSupportWaiting),
              );
              expect(
                wait.source,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(
                find.byType(SuiteProgressBar),
                source == 'pointer' ? findsOneWidget : findsNothing,
              );
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.tapAt(const Offset(4, 4));
              await t.pump();
              expect(outcome.done, isFalse);
              expect(outcome.route!.isActive, isTrue);
              p.gate.complete(true);
              await t.pump();
              if (source != 'pointer') {
                expect(outcome.route!.animation!.value, 0);
              }
              await t.pumpAndSettle();
              expect(outcome.done, isTrue);
              expect(
                outcome.value,
                isFalse,
                reason: 'false means a saved choice, not save failure.',
              );
              expect(
                outcome.source,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }
      testWidgets(
        '${suite.name}/$source adjust returns true without any save',
        (t) async {
          fixture.size(t, const Size(960, 900));
          final semantics = t.ensureSemantics();
          try {
            final p = FirstProbe(), outcome = FirstOutcome();
            await openFirst(t, p.dialog(), suite, outcome);
            await activateFirst(t, source, 'adjust');
            await t.pump();
            if (source != 'pointer') expect(outcome.route!.animation!.value, 0);
            await t.pumpAndSettle();
            expect(outcome.done, isTrue);
            expect(outcome.value, isTrue);
            expect(p.choices, isEmpty);
            expect(
              outcome.source,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
          } finally {
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
    for (final throws in [false, true]) {
      testWidgets(
        '${suite.name}/throw=$throws failure keeps dialog and retry gets a new static phase',
        (t) async {
          fixture.size(t, const Size(960, 900));
          var tries = 0;
          final gate = Completer<bool>(), outcome = FirstOutcome();
          final dialog = FirstUsePrivacyDialog(
            initial: firstInitial,
            onSave: (_) async {
              tries++;
              if (tries == 1) {
                if (throws) throw StateError('unconfirmed');
                return false;
              }
              return gate.future;
            },
          );
          await openFirst(t, dialog, suite, outcome);
          await activateFirst(t, 'pointer', 'accept');
          await t.pumpAndSettle();
          expect(find.text('尚未确认保存成功，请稍后重试。'), findsOneWidget);
          expect(outcome.done, isFalse);
          await activateFirst(t, 'keyboard', 'decline');
          await t.pump();
          final wait = t.widget<HelpSupportWaiting>(
            find.byType(HelpSupportWaiting),
          );
          expect(wait.key, const ValueKey(('first-privacy-wait', 2)));
          expect(wait.source, InteractionSource.keyboard);
          expect(find.byType(SuiteProgressBar), findsNothing);
          expect(tries, 2);
          gate.complete(true);
          await t.pump();
          await t.pump();
          expect(outcome.done, isTrue);
          expect(outcome.value, isFalse);
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
    testWidgets('${suite.name} unmount while saving ignores late success', (
      t,
    ) async {
      fixture.size(t, const Size(960, 900));
      final p = FirstProbe(), outcome = FirstOutcome();
      await openFirst(t, p.dialog(), suite, outcome);
      await activateFirst(t, 'pointer', 'accept');
      await t.pump();
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(const MaterialApp(home: Text('New owner')));
      p.gate.complete(true);
      await t.pumpAndSettle();
      expect(find.text('New owner'), findsOneWidget);
      expect(p.choices, hasLength(1));
      expect(t.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 45)));
  }
}
