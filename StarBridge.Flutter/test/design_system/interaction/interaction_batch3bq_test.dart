import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/account/account_login_dialog.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bg_test.dart' show activate;

class LoginPort implements AccountPort {
  LoginPort({bool hold = true})
    : delegate = InMemoryAccountAdapter(holdLoginUntilCancelled: hold);
  LoginPort.signedIn()
    : delegate = InMemoryAccountAdapter.forReview(AccountReviewState.signedIn);
  final InMemoryAccountAdapter delegate;
  final commands = <AccountPortCommand>[];
  Completer<AccountPortResult>? cancel;
  Completer<AccountPortResult>? held;
  Type? heldType;
  @override
  Stream<AccountInvalidation> get invalidations => delegate.invalidations;
  @override
  Future<AccountPortResult> read() => delegate.read();
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) {
    commands.add(command);
    if (command.runtimeType == heldType && held != null) return held!.future;
    if (command is CancelAccountLogin && cancel != null) return cancel!.future;
    return delegate.execute(command);
  }

  @override
  Future<void> close() => delegate.close();
}

StarBridgeActionButton button(WidgetTester t, String id) => t.widget(
  find.byWidgetPredicate(
    (w) => w is StarBridgeActionButton && w.controlKey == Key(id),
  ),
);
Future<void> open(
  WidgetTester t,
  AccountModule module,
  InteractionSuite suite,
  String source,
) async {
  await t.pumpWidget(scopedApp(AccountPage(module: module), suite));
  await t.pumpAndSettle();
  expect(button(t, 'account-login').onActivate, isNotNull);
  await activate(t, source, const Key('account-login'));
  await t.pump(const Duration(milliseconds: 350));
  await t.pump();
}

Future<void> clean(WidgetTester t, AccountModule module, LoginPort p) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  module.dispose();
  await t.runAsync(p.close);
  await t.pump();
}

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    adjacent(suite);
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final closeSource in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $source login and $closeSource cancellation preserve the original owner',
          (t) async {
            final p = LoginPort(),
                module = createAccountModule(p),
                semantics = t.ensureSemantics();
            try {
              await module.initialize();
              expect(p.commands, isEmpty);
              await open(t, module, suite, source);
              final target = find.byKey(const Key('account-login-dialog'));
              final route = ModalRoute.of(t.element(target));
              expect(route, isA<StarBridgeDialogRoute<void>>());
              expect(
                (route as StarBridgeDialogRoute).instant,
                source != 'pointer',
              );
              expect(
                MediaQuery.disableAnimationsOf(
                  t.element(find.byKey(const Key('account-login-motion'))),
                ),
                source != 'pointer',
              );
              expect(p.commands.whereType<BeginAccountLogin>(), hasLength(1));
              await activate(t, closeSource, const Key('account-cancel-login'));
              await t.pumpAndSettle();
              expect(target, findsNothing);
              expect(p.commands.whereType<CancelAccountLogin>(), hasLength(1));
              expect(p.commands.whereType<LogoutAccount>(), isEmpty);
            } finally {
              await clean(t, module, p);
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets('$suite late cancellation closes only the owned login route', (
      t,
    ) async {
      final p = LoginPort(), module = createAccountModule(p);
      try {
        await module.initialize();
        await open(t, module, suite, 'pointer');
        p.cancel = Completer<AccountPortResult>();
        await activate(t, 'pointer', const Key('account-cancel-login'));
        await t.pump();
        expect(button(t, 'account-cancel-login').onActivate, isNull);
        final context = t.element(
          find.byKey(const Key('account-login-dialog')),
        );
        unawaited(
          showStarBridgeDialog(
            context,
            builder: (_) =>
                const AlertDialog(content: Text('new unrelated dialog')),
          ),
        );
        await t.pump(const Duration(milliseconds: 350));
        p.cancel!.complete(AccountPortResult.cancelled(p.delegate.snapshot));
        p.cancel = null;
        await t.pumpAndSettle();
        expect(find.text('new unrelated dialog'), findsOneWidget);
        expect(find.byKey(const Key('account-login-dialog')), findsNothing);
        expect(p.commands.whereType<CancelAccountLogin>(), hasLength(1));
      } finally {
        await clean(t, module, p);
      }
    });
    testWidgets(
      '$suite Escape waits for cancellation acknowledgement then exits immediately',
      (t) async {
        final p = LoginPort(), module = createAccountModule(p);
        try {
          await module.initialize();
          await open(t, module, suite, 'pointer');
          p.cancel = Completer<AccountPortResult>();
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          expect(find.byKey(const Key('account-login-dialog')), findsOneWidget);
          p.cancel!.complete(AccountPortResult.cancelled(p.delegate.snapshot));
          p.cancel = null;
          await t.pump();
          await t.pump();
          expect(find.byKey(const Key('account-login-dialog')), findsNothing);
          expect(p.commands.whereType<LogoutAccount>(), isEmpty);
        } finally {
          await clean(t, module, p);
        }
      },
    );
  }
}

void adjacent(InteractionSuite suite) {
  testWidgets(
    '$suite settled SCM success is not replayed when motion returns',
    (t) async {
      final p = LoginPort(hold: false), module = createAccountModule(p);
      try {
        await module.initialize();
        await open(t, module, suite, 'pointer');
        await t.runAsync(ScmSuccessMotion.verifyArtwork);
        await t.pumpAndSettle();
        await t.pumpWidget(
          scopedApp(AccountPage(module: module), suite, reduce: true),
        );
        await t.pump();
        await t.pump();
        final painter = t
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(const Key('account-login-motion')),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!;
        var ticks = 0;
        void tick() => ticks++;
        painter.addListener(tick);
        await t.pumpWidget(scopedApp(AccountPage(module: module), suite));
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(ticks, 0);
        painter.removeListener(tick);
        expect(p.commands.whereType<BeginAccountLogin>(), hasLength(1));
        expect(
          t
              .widget<ScmSuccessMotion>(
                find.byKey(const Key('account-login-motion')),
              )
              .play,
          isTrue,
        );
        await activate(t, 'keyboard', const Key('account-cancel-login'));
        await t.pumpAndSettle();
      } finally {
        await clean(t, module, p);
      }
    },
  );
  testWidgets('$suite one login flow and live reduced-motion waiting', (
    t,
  ) async {
    final p = LoginPort(), module = createAccountModule(p);
    try {
      await module.initialize();
      await open(t, module, suite, 'pointer');
      final page = t.element(find.byType(AccountPage));
      await showAccountLoginDialog(page, module);
      expect(p.commands.whereType<BeginAccountLogin>(), hasLength(1));
      expect(find.byKey(const Key('account-login-dialog')), findsOneWidget);
      await t.runAsync(ScmSuccessMotion.verifyArtwork);
      await t.pump();
      await t.pumpWidget(
        scopedApp(
          AccountPage(module: module),
          suite,
          reduce: true,
          light: true,
        ),
      );
      await t.pump();
      await t.pump();
      expect(
        MediaQuery.disableAnimationsOf(
          t.element(find.byKey(const Key('account-login-motion'))),
        ),
        isTrue,
      );
      final painter = t
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(const Key('account-login-motion')),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      var ticks = 0;
      void tick() => ticks++;
      painter.addListener(tick);
      await t.pump(const Duration(milliseconds: 100));
      expect(
        ticks,
        0,
        reason: 'Inspect only the SCM clock, not unrelated page tickers',
      );
      await t.pumpWidget(scopedApp(AccountPage(module: module), suite));
      await t.pump();
      await t.pump();
      expect(
        MediaQuery.disableAnimationsOf(
          t.element(find.byKey(const Key('account-login-motion'))),
        ),
        isFalse,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(
        ticks,
        greaterThan(0),
        reason: 'Normal loading resumes without starting a second auth request',
      );
      painter.removeListener(tick);
      expect(p.commands.whereType<BeginAccountLogin>(), hasLength(1));
      await activate(t, 'keyboard', const Key('account-cancel-login'));
      await t.pumpAndSettle();
    } finally {
      await clean(t, module, p);
    }
  });
  testWidgets('$suite locked generic dialog is not dismissed by Escape', (
    t,
  ) async {
    await t.pumpWidget(scopedApp(const Scaffold(body: Text('page')), suite));
    await t.pumpAndSettle();
    final context = t.element(find.text('page'));
    unawaited(
      showStarBridgeDialog(
        context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Text('locked')),
      ),
    );
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('locked'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });
  for (final source in ['pointer', 'keyboard', 'reader']) {
    testWidgets('$suite $source login success retains the dialog until close', (
      t,
    ) async {
      final p = LoginPort(hold: false),
          module = createAccountModule(p),
          semantics = t.ensureSemantics();
      try {
        await module.initialize();
        await open(t, module, suite, source);
        expect(module.projection.value.isSignedIn, isTrue);
        final motion = t.widget<ScmSuccessMotion>(
          find.byKey(const Key('account-login-motion')),
        );
        expect(motion.play, isTrue);
        expect(motion.loading, isFalse);
        expect(find.byKey(const Key('account-login-dialog')), findsOneWidget);
        await activate(t, source, const Key('account-cancel-login'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('account-login-dialog')), findsNothing);
        expect(p.commands.whereType<CancelAccountLogin>(), isEmpty);
        expect(p.commands.whereType<LogoutAccount>(), isEmpty);
      } finally {
        await clean(t, module, p);
        semantics.dispose();
      }
    });
    testWidgets(
      '$suite $source refused cancellation remains retryable without duplicate requests',
      (t) async {
        final p = LoginPort(),
            module = createAccountModule(p),
            semantics = t.ensureSemantics();
        try {
          await module.initialize();
          await open(t, module, suite, source);
          p.cancel = Completer<AccountPortResult>();
          await activate(t, source, const Key('account-cancel-login'));
          await t.pump();
          expect(button(t, 'account-cancel-login').onActivate, isNull);
          expect(p.commands.whereType<CancelAccountLogin>(), hasLength(1));
          p.cancel!.complete(
            const AccountPortResult.failed(
              AccountFailure(
                code: 'refused',
                messageKey: 'account.login.cancelled',
                retryable: true,
              ),
            ),
          );
          p.cancel = null;
          await t.pump();
          await t.pump();
          expect(find.byKey(const Key('account-login-dialog')), findsOneWidget);
          expect(button(t, 'account-login-retry').onActivate, isNotNull);
          await activate(t, source, const Key('account-login-retry'));
          await t.pump();
          expect(p.commands.whereType<BeginAccountLogin>(), hasLength(2));
          await activate(t, source, const Key('account-cancel-login'));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('account-login-dialog')), findsNothing);
          expect(p.commands.whereType<LogoutAccount>(), isEmpty);
        } finally {
          await clean(t, module, p);
          semantics.dispose();
        }
      },
    );
    for (final logout in [false, true]) {
      testWidgets(
        '$suite $source ${logout ? 'logout' : 'cache'} waits for acknowledgement and allows retry after refusal',
        (t) async {
          final p = LoginPort.signedIn(),
              module = createAccountModule(p),
              semantics = t.ensureSemantics();
          final key = Key(logout ? 'account-logout' : 'account-clear-cache');
          p.heldType = logout ? LogoutAccount : ClearAccountProfileCache;
          p.held = Completer<AccountPortResult>();
          try {
            await module.initialize();
            await t.pumpWidget(scopedApp(AccountPage(module: module), suite));
            await t.pumpAndSettle();
            await t.ensureVisible(find.byKey(key));
            await activate(t, source, key);
            await t.pump();
            expect(
              button(
                t,
                logout ? 'account-logout' : 'account-clear-cache',
              ).onActivate,
              isNull,
            );
            expect(p.commands, hasLength(1));
            expect(module.projection.value.isSignedIn, isTrue);
            p.held!.complete(
              const AccountPortResult.failed(
                AccountFailure(
                  code: 'refused',
                  messageKey: 'account.login.cancelled',
                  retryable: true,
                ),
              ),
            );
            p.held = null;
            await t.pumpAndSettle();
            expect(module.projection.value.isSignedIn, isTrue);
            expect(
              button(
                t,
                logout ? 'account-logout' : 'account-clear-cache',
              ).onActivate,
              isNotNull,
            );
            await t.ensureVisible(find.byKey(key));
            await activate(t, source, key);
            await t.pumpAndSettle();
            expect(p.commands, hasLength(2));
            expect(module.projection.value.isSignedIn, !logout);
          } finally {
            await clean(t, module, p);
            semantics.dispose();
          }
        },
      );
    }
  }
}
