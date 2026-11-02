import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/legacy_password_login.dart';
import 'package:starbridge_flutter/features/account/legacy_password_login_dialog.dart';

import 'interaction_batch3bq_test.dart' show button;
import 'interaction_batch3bt_test.dart' show NestedRecoveryPort, clean, hit;
import 'interaction_batch3i_test.dart' show scopedApp;

class LoginPort extends NestedRecoveryPort {
  bool loginSupported = true;
  @override
  bool get supportsLegacyPasswordLogin => loginSupported;
  Completer<LegacyPasswordLoginResult>? pendingLogin;
  Completer<void>? cancelLogin;
  LegacyPasswordLoginResult result = const LegacyPasswordLoginResult(
    'verified',
  );
  final inputs = <(String, String)>[];
  @override
  Future<LegacyPasswordLoginResult> loginLegacy(String email, String password) {
    logins++;
    inputs.add((email, password));
    return pendingLogin?.future ?? Future.value(result);
  }

  @override
  Future<void> cancelLegacyPasswordLogin() async {
    loginCancels++;
    await cancelLogin?.future;
  }
}

Future<void> cleanup(WidgetTester t, AccountModule m, LoginPort p) async {
  if (p.pendingLogin != null && !p.pendingLogin!.isCompleted) {
    p.pendingLogin!.complete(const LegacyPasswordLoginResult('cancelled'));
  }
  if (p.cancelLogin != null && !p.cancelLogin!.isCompleted) {
    p.cancelLogin!.complete();
  }
  await clean(t, m, p);
}

Future<void> open(
  WidgetTester t,
  AccountModule m,
  LoginPort p,
  InteractionSuite suite,
  String source,
) async {
  await t.pumpWidget(scopedApp(AccountPage(module: m), suite));
  await t.pumpAndSettle();
  expect(button(t, 'account-legacy-login').onActivate, isNotNull);
  await hit(t, source, 'account-legacy-login');
  await t.pumpAndSettle();
  final route = ModalRoute.of(
    t.element(find.byKey(const Key('legacy-login-email'))),
  );
  expect(route, isA<StarBridgeDialogRoute<void>>());
  expect((route as StarBridgeDialogRoute).instant, source != 'pointer');
  expect(find.byType(StarBridgeFieldFrame), findsNWidgets(2));
  expect(p.logins, 0);
}

Future<void> credentials(WidgetTester t) async {
  await t.enterText(
    find.byKey(const Key('legacy-login-email')),
    'old@example.invalid',
  );
  await t.enterText(
    find.byKey(const Key('legacy-login-password')),
    'unit-test-only',
  );
}

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite live reduce/theme preserves login controller and settles wait',
      (t) async {
        final p = LoginPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await credentials(t);
          final controller = t
              .widget<TextField>(find.byKey(const Key('legacy-login-email')))
              .controller!;
          p.pendingLogin = Completer<LegacyPasswordLoginResult>();
          await hit(t, 'pointer', 'legacy-login-submit');
          await t.pumpWidget(
            scopedApp(AccountPage(module: m), suite, reduce: true, light: true),
          );
          await t.pump();
          await t.pump();
          expect(
            identical(
              t
                  .widget<TextField>(
                    find.byKey(const Key('legacy-login-email')),
                  )
                  .controller,
              controller,
            ),
            isTrue,
          );
          expect(controller.text, 'old@example.invalid');
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          await hit(t, 'keyboard', 'legacy-login-close');
          await t.pumpAndSettle();
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets('$suite capability loss closes only login and clears secret', (
      t,
    ) async {
      final p = LoginPort(), m = createAccountModule(p);
      try {
        await m.initialize();
        await open(t, m, p, suite, 'pointer');
        await credentials(t);
        final controller = t
            .widget<TextField>(find.byKey(const Key('legacy-login-password')))
            .controller!;
        p.loginSupported = false;
        t.binding.scheduleFrame();
        await t.pump();
        await t.pump();
        expect(find.byKey(const Key('legacy-login-password')), findsNothing);
        expect(controller.text, isEmpty);
        expect(p.logins, 0);
        expect(p.loginCancels, 1);
      } finally {
        await cleanup(t, m, p);
      }
    });
    testWidgets('$suite short server throttle expires without queued login', (
      t,
    ) async {
      final p = LoginPort(), m = createAccountModule(p);
      p.result = const LegacyPasswordLoginResult(
        'throttled',
        retryAfterSeconds: 1,
      );
      try {
        await m.initialize();
        await open(t, m, p, suite, 'pointer');
        await credentials(t);
        await hit(t, 'pointer', 'legacy-login-submit');
        await t.pumpAndSettle();
        expect(button(t, 'legacy-login-submit').onActivate, isNull);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1100)),
        );
        await t.pump(const Duration(seconds: 1));
        await t.pump();
        expect(button(t, 'legacy-login-submit').onActivate, isNotNull);
        expect(p.logins, 1);
        await hit(t, 'keyboard', 'legacy-login-skip');
        await t.pumpAndSettle();
      } finally {
        await cleanup(t, m, p);
      }
    });
    for (final opening in ['pointer', 'keyboard', 'reader']) {
      for (final acting in ['pointer', 'keyboard', 'reader']) {
        for (final outcome in ['verified', 'unavailable', 'throttled']) {
          testWidgets(
            '$suite $opening to $acting legacy login $outcome preserves receipt and secrets',
            (t) async {
              final p = LoginPort(),
                  m = createAccountModule(p),
                  semantics = t.ensureSemantics();
              try {
                await m.initialize();
                await open(t, m, p, suite, opening);
                await credentials(t);
                final password = t
                    .widget<TextField>(
                      find.byKey(const Key('legacy-login-password')),
                    )
                    .controller!;
                p.pendingLogin = Completer<LegacyPasswordLoginResult>();
                final old = button(t, 'legacy-login-submit').onActivate!;
                await hit(t, acting, 'legacy-login-submit');
                old(InteractionSource.pointer);
                expect(p.logins, 1);
                expect(p.inputs.single, (
                  'old@example.invalid',
                  'unit-test-only',
                ));
                expect(button(t, 'legacy-login-submit').onActivate, isNull);
                expect(button(t, 'legacy-login-skip').onActivate, isNull);
                expect(
                  InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                      .reduceMotion,
                  acting != 'pointer',
                );
                p.pendingLogin!.complete(
                  LegacyPasswordLoginResult(
                    outcome,
                    retryAfterSeconds: outcome == 'throttled' ? 60 : 0,
                  ),
                );
                p.pendingLogin = null;
                await t.pumpAndSettle();
                expect(password.text, isEmpty);
                if (outcome == 'verified') {
                  expect(
                    find.byKey(const Key('legacy-login-email')),
                    findsNothing,
                  );
                  expect(p.loginCancels, 1);
                } else {
                  expect(
                    find.byKey(const Key('legacy-login-result')),
                    findsOneWidget,
                  );
                  expect(
                    button(t, 'legacy-login-submit').onActivate == null,
                    outcome == 'throttled',
                  );
                  await hit(t, acting, 'legacy-login-close');
                  await t.pumpAndSettle();
                }
                expect(p.delegate.commands, isEmpty);
              } finally {
                await cleanup(t, m, p);
                semantics.dispose();
              }
            },
          );
        }
      }
      testWidgets(
        '$suite $opening close pending login ignores late verification',
        (t) async {
          final p = LoginPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await open(t, m, p, suite, 'pointer');
            await credentials(t);
            p.pendingLogin = Completer<LegacyPasswordLoginResult>();
            await hit(t, opening, 'legacy-login-submit');
            await hit(t, opening, 'legacy-login-close');
            await t.pumpAndSettle();
            expect(p.loginCancels, 1);
            final context = t.element(find.byType(AccountPage));
            unawaited(
              showStarBridgeDialog(
                context,
                builder: (_) => const AlertDialog(content: Text('unrelated')),
              ),
            );
            await t.pumpAndSettle();
            p.pendingLogin!.complete(
              const LegacyPasswordLoginResult('verified'),
            );
            p.pendingLogin = null;
            await t.pumpAndSettle();
            expect(find.text('unrelated'), findsOneWidget);
            expect(p.delegate.commands, isEmpty);
          } finally {
            await cleanup(t, m, p);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite verification under unrelated top route retires only login',
      (t) async {
        final p = LoginPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await credentials(t);
          p.pendingLogin = Completer<LegacyPasswordLoginResult>();
          await hit(t, 'pointer', 'legacy-login-submit');
          final context = t.element(
            find.byKey(const Key('legacy-login-email')),
          );
          unawaited(
            showStarBridgeDialog(
              context,
              builder: (_) => const AlertDialog(content: Text('unrelated')),
            ),
          );
          for (var frame = 0; frame < 25; frame++) {
            await t.pump(const Duration(milliseconds: 16));
          }
          p.pendingLogin!.complete(const LegacyPasswordLoginResult('verified'));
          p.pendingLogin = null;
          await t.pumpAndSettle();
          expect(find.text('unrelated'), findsOneWidget);
          expect(find.byKey(const Key('legacy-login-email')), findsNothing);
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite owner replacement retires login and stale callback does not write',
      (t) async {
        final p = LoginPort(),
            m = createAccountModule(p),
            q = LoginPort(),
            next = createAccountModule(q);
        try {
          await m.initialize();
          await next.initialize();
          await open(t, m, p, suite, 'pointer');
          await credentials(t);
          final old = button(t, 'legacy-login-submit').onActivate!;
          await t.pumpWidget(scopedApp(AccountPage(module: next), suite));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('legacy-login-email')), findsNothing);
          old(InteractionSource.pointer);
          await t.pumpAndSettle();
          expect(p.logins, 0);
          expect(q.logins, 0);
        } finally {
          await cleanup(t, m, p);
          next.dispose();
          await t.runAsync(q.close);
        }
      },
    );
    testWidgets(
      '$suite empty validation and IME done keep original login method',
      (t) async {
        final p = LoginPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await hit(t, 'pointer', 'legacy-login-submit');
          expect(p.logins, 0);
          await credentials(t);
          p.pendingLogin = Completer<LegacyPasswordLoginResult>();
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pump();
          await t.pump();
          expect(p.logins, 1);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          await hit(t, 'keyboard', 'legacy-login-close');
          await t.pumpAndSettle();
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite single port lease persists through asynchronous cleanup',
      (t) async {
        final p = LoginPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          final context = t.element(find.byType(AccountPage));
          await showLegacyPasswordLoginDialog(context, p);
          expect(find.byKey(const Key('legacy-login-email')), findsOneWidget);
          p.cancelLogin = Completer<void>();
          await hit(t, 'pointer', 'legacy-login-close');
          await t.pumpAndSettle();
          await showLegacyPasswordLoginDialog(context, p);
          expect(find.byKey(const Key('legacy-login-email')), findsNothing);
          p.cancelLogin!.complete();
          p.cancelLogin = null;
          await t.pump();
          await t.pump();
          unawaited(showLegacyPasswordLoginDialog(context, p));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('legacy-login-email')), findsOneWidget);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.byKey(const Key('legacy-login-email')), findsNothing);
        } finally {
          await cleanup(t, m, p);
        }
      },
    );
  }
}
