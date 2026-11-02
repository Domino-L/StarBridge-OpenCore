import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/account/password_recovery.dart';
import 'package:starbridge_flutter/features/account/password_recovery_dialog.dart';
import 'package:starbridge_flutter/features/account/legacy_password_login.dart';

import 'interaction_batch3bg_test.dart' show activate;
import 'interaction_batch3bq_test.dart' show button;
import 'interaction_batch3i_test.dart' show scopedApp;

class RecoveryPort implements AccountPort, PasswordRecoveryPort {
  RecoveryPort({bool signedIn = false})
    : delegate = InMemoryAccountAdapter.forReview(
        signedIn ? AccountReviewState.signedIn : AccountReviewState.signedOut,
      );
  final InMemoryAccountAdapter delegate;
  bool supported = true;
  int sends = 0, resets = 0, cancels = 0;
  final submitted = <(String, String, String)>[];
  PasswordRecoveryResult sendResult = const PasswordRecoveryResult(
    'codeRequested',
  );
  Completer<PasswordRecoveryResult>? pending;
  Completer<void>? cancelPending;
  @override
  bool get supportsPasswordRecovery => supported;
  @override
  Stream<AccountInvalidation> get invalidations => delegate.invalidations;
  @override
  Future<AccountPortResult> read() => delegate.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) =>
      delegate.execute(command);
  @override
  Future<void> close() => delegate.close();
  @override
  Future<PasswordRecoveryResult> sendPasswordResetCode(String email) {
    sends++;
    return pending?.future ?? Future.value(sendResult);
  }

  @override
  Future<PasswordRecoveryResult> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) {
    resets++;
    submitted.add((email, code, password));
    return pending?.future ??
        Future.value(const PasswordRecoveryResult('reset'));
  }

  @override
  Future<void> cancelPasswordRecovery() async {
    cancels++;
    await cancelPending?.future;
  }
}

class NestedRecoveryPort extends RecoveryPort
    implements LegacyPasswordLoginPort {
  int logins = 0, loginCancels = 0;
  @override
  bool get supportsLegacyPasswordLogin => true;
  @override
  Future<LegacyPasswordLoginResult> loginLegacy(
    String email,
    String password,
  ) async {
    logins++;
    return const LegacyPasswordLoginResult('unavailable');
  }

  @override
  Future<void> cancelLegacyPasswordLogin() async {
    loginCancels++;
  }
}

Future<void> clean(WidgetTester t, AccountModule m, RecoveryPort p) async {
  if (p.pending != null && !p.pending!.isCompleted) {
    p.pending!.complete(const PasswordRecoveryResult('cancelled'));
  }
  if (p.cancelPending != null && !p.cancelPending!.isCompleted) {
    p.cancelPending!.complete();
  }
  await t.pumpWidget(const SizedBox());
  await t.pump();
  m.dispose();
  await t.runAsync(p.close);
  await t.pump();
}

Future<void> open(
  WidgetTester t,
  AccountModule m,
  RecoveryPort p,
  InteractionSuite suite,
  String source,
) async {
  await t.pumpWidget(scopedApp(AccountPage(module: m), suite));
  await t.pumpAndSettle();
  final key = p.delegate.snapshot.sessionState == AccountSessionState.signedIn
      ? 'account-linked-password-recovery'
      : 'account-password-recovery';
  expect(button(t, key).onActivate, isNotNull);
  await t.ensureVisible(find.byKey(Key(key)));
  await activate(t, source, Key(key));
  await t.pumpAndSettle();
  expect(
    ModalRoute.of(t.element(find.byKey(const Key('recovery-email')))),
    isA<StarBridgeDialogRoute<void>>(),
  );
  expect(find.byType(StarBridgeFieldFrame), findsNWidgets(4));
  expect(p.sends, 0);
  expect(p.resets, 0);
}

Future<void> hit(WidgetTester t, String source, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await activate(t, source, Key(key));
}

Future<void> credentials(WidgetTester t) async {
  await t.enterText(
    find.byKey(const Key('recovery-email')),
    'old@example.invalid',
  );
  await t.enterText(find.byKey(const Key('recovery-code')), '123456');
  await t.enterText(
    find.byKey(const Key('recovery-password')),
    'unit-test-only',
  );
  await t.enterText(
    find.byKey(const Key('recovery-confirm-password')),
    'unit-test-only',
  );
}

String text(WidgetTester t, String key) =>
    t.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite filled email label remains above its value when busy disables editing',
      (t) async {
        final p = RecoveryPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await t.pumpWidget(
            scopedApp(AccountPage(module: m), suite, light: true),
          );
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('recovery-email')),
            'old@example.invalid',
          );
          await t.pump(const Duration(milliseconds: 250));
          p.pending = Completer<PasswordRecoveryResult>();
          await hit(t, 'pointer', 'recovery-send');
          for (var frame = 0; frame < 20; frame++) {
            await t.pump(const Duration(milliseconds: 16));
          }
          final field = find.byKey(const Key('recovery-email'));
          Rect bounds(Finder finder) {
            final box = t.renderObject<RenderBox>(finder);
            return Rect.fromPoints(
              box.localToGlobal(Offset.zero),
              box.localToGlobal(box.size.bottomRight(Offset.zero)),
            );
          }

          final label = bounds(
            find.descendant(of: field, matching: find.text('旧账号邮箱')),
          );
          final value = bounds(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(
            label.bottom,
            lessThanOrEqualTo(value.top),
            reason: 'Filled label must not be painted over the value',
          );
        } finally {
          await clean(t, m, p);
        }
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source recovery nested in legacy login returns to its parent',
        (t) async {
          final p = NestedRecoveryPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await t.pumpWidget(scopedApp(AccountPage(module: m), suite));
            await t.pumpAndSettle();
            await hit(t, 'pointer', 'account-legacy-login');
            await t.pumpAndSettle();
            expect(button(t, 'legacy-login-recovery').onActivate, isNotNull);
            await hit(t, source, 'legacy-login-recovery');
            await t.pumpAndSettle();
            expect(
              (ModalRoute.of(
                t.element(find.byKey(const Key('recovery-email'))),
              ) as StarBridgeDialogRoute).instant,
              source != 'pointer',
            );
            await hit(t, source, 'recovery-close');
            await t.pumpAndSettle();
            expect(find.byKey(const Key('legacy-login-email')), findsOneWidget);
            expect(p.cancels, 1);
            expect(p.logins, 0);
            await t.tap(find.byKey(const Key('legacy-login-close')));
            await t.pumpAndSettle();
            expect(p.loginCancels, 1);
          } finally {
            await clean(t, m, p);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite input validators and digit formatter do not send invalid recovery commands',
      (t) async {
        final p = RecoveryPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await hit(t, 'pointer', 'recovery-send');
          expect(p.sends, 0);
          await t.enterText(
            find.byKey(const Key('recovery-email')),
            'old@example.invalid',
          );
          await hit(t, 'pointer', 'recovery-submit');
          expect(p.resets, 0);
          await t.enterText(
            find.byKey(const Key('recovery-code')),
            '123abc456789',
          );
          expect(text(t, 'recovery-code'), '123456');
          await t.enterText(
            find.byKey(const Key('recovery-password')),
            'short',
          );
          await hit(t, 'pointer', 'recovery-submit');
          expect(p.resets, 0);
          await t.enterText(
            find.byKey(const Key('recovery-password')),
            'unit-test-only',
          );
          await t.enterText(
            find.byKey(const Key('recovery-confirm-password')),
            'different-value',
          );
          await hit(t, 'pointer', 'recovery-submit');
          expect(p.resets, 0);
          expect(p.delegate.commands, isEmpty);
          await hit(t, 'keyboard', 'recovery-close');
          await t.pumpAndSettle();
        } finally {
          await clean(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite real short deadline releases throttled controls without queued replay',
      (t) async {
        final p = RecoveryPort(), m = createAccountModule(p);
        p.sendResult = const PasswordRecoveryResult(
          'throttled',
          retryAfterSeconds: 1,
        );
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await credentials(t);
          await hit(t, 'pointer', 'recovery-send');
          await t.pumpAndSettle();
          expect(button(t, 'recovery-submit').onActivate, isNull);
          // Production uses DateTime.now. Advance wall time as well as fake timer time.
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1100)),
          );
          await t.pump(const Duration(seconds: 1));
          await t.pump();
          expect(button(t, 'recovery-submit').onActivate, isNotNull);
          expect(button(t, 'recovery-send').onActivate, isNotNull);
          expect(p.sends, 1);
          expect(p.resets, 0);
          await hit(t, 'keyboard', 'recovery-close');
          await t.pumpAndSettle();
        } finally {
          await clean(t, m, p);
        }
      },
    );
    for (final signedIn in [false, true]) {
      for (final opening in ['pointer', 'keyboard', 'reader']) {
        for (final acting in ['pointer', 'keyboard', 'reader']) {
          testWidgets(
            '$suite signedIn=$signedIn $opening to $acting recovery preserves send/reset receipts and source',
            (t) async {
              final p = RecoveryPort(signedIn: signedIn),
                  m = createAccountModule(p),
                  semantics = t.ensureSemantics();
              try {
                await m.initialize();
                await open(t, m, p, suite, opening);
                expect(
                  (ModalRoute.of(
                    t.element(find.byKey(const Key('recovery-email'))),
                  ) as StarBridgeDialogRoute).instant,
                  opening != 'pointer',
                );
                await credentials(t);
                p.pending = Completer<PasswordRecoveryResult>();
                final oldSend = button(t, 'recovery-send').onActivate!;
                await hit(t, acting, 'recovery-send');
                oldSend(InteractionSource.pointer);
                expect(p.sends, 1);
                expect(button(t, 'recovery-send').onActivate, isNull);
                expect(button(t, 'recovery-submit').onActivate, isNull);
                expect(
                  InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                      .reduceMotion,
                  acting != 'pointer',
                );
                p.pending!.complete(
                  const PasswordRecoveryResult('codeRequested'),
                );
                p.pending = null;
                await t.pumpAndSettle();
                expect(text(t, 'recovery-email'), 'old@example.invalid');
                p.pending = Completer<PasswordRecoveryResult>();
                await hit(t, acting, 'recovery-submit');
                expect(p.resets, 1);
                expect(p.submitted.single, (
                  'old@example.invalid',
                  '123456',
                  'unit-test-only',
                ));
                expect(
                  InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                      .reduceMotion,
                  acting != 'pointer',
                );
                p.pending!.complete(const PasswordRecoveryResult('reset'));
                p.pending = null;
                await t.pumpAndSettle();
                expect(text(t, 'recovery-password'), isEmpty);
                expect(text(t, 'recovery-confirm-password'), isEmpty);
                expect(text(t, 'recovery-code'), isEmpty);
                expect(p.delegate.commands, isEmpty);
                await hit(t, acting, 'recovery-close');
                await t.pumpAndSettle();
                expect(find.byKey(const Key('recovery-result')), findsNothing);
                expect(p.cancels, 1);
              } finally {
                await clean(t, m, p);
                semantics.dispose();
              }
            },
          );
        }
      }
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source closing pending recovery ignores late result and does not pop unrelated route',
        (t) async {
          final p = RecoveryPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await open(t, m, p, suite, 'pointer');
            await credentials(t);
            p.pending = Completer<PasswordRecoveryResult>();
            await hit(t, source, 'recovery-send');
            final ownedContext = t.element(
              find.byKey(const Key('recovery-email')),
            );
            await hit(t, source, 'recovery-close');
            await t.pumpAndSettle();
            expect(p.cancels, 1);
            final pageContext = t.element(find.byType(AccountPage));
            unawaited(
              showStarBridgeDialog(
                pageContext,
                builder: (_) => const AlertDialog(content: Text('unrelated')),
              ),
            );
            await t.pumpAndSettle();
            expect(ownedContext.mounted, isFalse);
            p.pending!.complete(const PasswordRecoveryResult('codeRequested'));
            p.pending = null;
            await t.pumpAndSettle();
            expect(find.text('unrelated'), findsOneWidget);
            expect(find.byKey(const Key('recovery-result')), findsNothing);
          } finally {
            await clean(t, m, p);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source failed reset clears secrets but keeps email/code for retry',
        (t) async {
          final p = RecoveryPort(),
              m = createAccountModule(p),
              semantics = t.ensureSemantics();
          try {
            await m.initialize();
            await open(t, m, p, suite, source);
            await credentials(t);
            p.pending = Completer<PasswordRecoveryResult>();
            await hit(t, source, 'recovery-submit');
            p.pending!.complete(const PasswordRecoveryResult('unavailable'));
            p.pending = null;
            await t.pumpAndSettle();
            expect(text(t, 'recovery-password'), isEmpty);
            expect(text(t, 'recovery-confirm-password'), isEmpty);
            expect(text(t, 'recovery-email'), 'old@example.invalid');
            expect(text(t, 'recovery-code'), '123456');
            expect(button(t, 'recovery-submit').onActivate, isNotNull);
            await credentials(t);
            await hit(t, source, 'recovery-submit');
            await t.pumpAndSettle();
            expect(p.resets, 2);
            await hit(t, source, 'recovery-close');
            await t.pumpAndSettle();
          } finally {
            await clean(t, m, p);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite one recovery per port remains locked until exit cleanup completes',
      (t) async {
        final p = RecoveryPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          final context = t.element(find.byType(AccountPage));
          await showPasswordRecoveryDialog(context, p);
          expect(find.byKey(const Key('recovery-email')), findsOneWidget);
          p.cancelPending = Completer<void>();
          await hit(t, 'pointer', 'recovery-close');
          await t.pumpAndSettle();
          expect(p.cancels, 1);
          await showPasswordRecoveryDialog(context, p);
          await t.pump();
          expect(find.byKey(const Key('recovery-email')), findsNothing);
          p.cancelPending!.complete();
          p.cancelPending = null;
          await t.pump();
          await t.pump();
          unawaited(showPasswordRecoveryDialog(context, p));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('recovery-email')), findsOneWidget);
          await hit(t, 'keyboard', 'recovery-close');
          await t.pumpAndSettle();
          expect(p.cancels, 2);
        } finally {
          await clean(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite capability loss retires recovery and clears the editable secret',
      (t) async {
        final p = RecoveryPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await credentials(t);
          final controller = t
              .widget<TextField>(find.byKey(const Key('recovery-password')))
              .controller!;
          p.supported = false;
          t.binding.scheduleFrame();
          await t.pump();
          await t.pump();
          expect(find.byKey(const Key('recovery-password')), findsNothing);
          expect(controller.text, isEmpty);
          expect(p.cancels, 1);
          expect(p.resets, 0);
        } finally {
          await clean(t, m, p);
        }
      },
    );
    testWidgets(
      '$suite replacement account retires only recovery and ignores old action',
      (t) async {
        final p = RecoveryPort(),
            m = createAccountModule(p),
            q = RecoveryPort(),
            next = createAccountModule(q);
        try {
          await m.initialize();
          await next.initialize();
          await open(t, m, p, suite, 'pointer');
          await credentials(t);
          final old = button(t, 'recovery-submit').onActivate!;
          final context = t.element(find.byKey(const Key('recovery-email')));
          unawaited(
            showStarBridgeDialog(
              context,
              builder: (_) => const AlertDialog(content: Text('unrelated')),
            ),
          );
          await t.pumpAndSettle();
          await t.pumpWidget(scopedApp(AccountPage(module: next), suite));
          await t.pumpAndSettle();
          expect(find.text('unrelated'), findsOneWidget);
          expect(find.byKey(const Key('recovery-email')), findsNothing);
          old(InteractionSource.pointer);
          await t.pumpAndSettle();
          expect(p.resets, 0);
          expect(q.resets, 0);
        } finally {
          await clean(t, m, p);
          next.dispose();
          await t.runAsync(q.close);
        }
      },
    );
    for (final throttled in [true, false]) {
      testWidgets(
        '$suite cooldown throttled=$throttled preserves the two distinct gates',
        (t) async {
          final p = RecoveryPort(), m = createAccountModule(p);
          p.sendResult = PasswordRecoveryResult(
            throttled ? 'throttled' : 'codeRequested',
            retryAfterSeconds: 60,
          );
          try {
            await m.initialize();
            await open(t, m, p, suite, 'pointer');
            await credentials(t);
            await hit(t, 'pointer', 'recovery-send');
            await t.pumpAndSettle();
            expect(button(t, 'recovery-send').onActivate, isNull);
            expect(button(t, 'recovery-submit').onActivate == null, throttled);
            await hit(t, 'keyboard', 'recovery-close');
            await t.pumpAndSettle();
          } finally {
            await clean(t, m, p);
          }
        },
      );
    }
    testWidgets(
      '$suite live theme/reduce preserves editor and settles waiting',
      (t) async {
        final p = RecoveryPort(), m = createAccountModule(p);
        try {
          await m.initialize();
          await open(t, m, p, suite, 'pointer');
          await credentials(t);
          final controller = t
              .widget<TextField>(find.byKey(const Key('recovery-email')))
              .controller!;
          p.pending = Completer<PasswordRecoveryResult>();
          await hit(t, 'pointer', 'recovery-send');
          await t.pumpWidget(
            scopedApp(AccountPage(module: m), suite, reduce: true, light: true),
          );
          await t.pump();
          await t.pump();
          expect(
            identical(
              t
                  .widget<TextField>(find.byKey(const Key('recovery-email')))
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
          expect(
            Theme.of(t.element(find.byKey(const Key('recovery-email'))))
                .brightness,
            Brightness.light,
          );
          await hit(t, 'keyboard', 'recovery-close');
          await t.pumpAndSettle();
        } finally {
          await clean(t, m, p);
        }
      },
    );
  }
}
